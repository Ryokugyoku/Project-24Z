import Foundation
import GRDB

/// GRDBをSystem of Recordとする端末別既定Adapter候補Repositoryです。
final class GRDBDefaultAdapterRepository: DefaultAdapterRepository {
    /// 起動時検査済みのUser Scope専用Poolです。
    private let databasePool: DatabasePool

    /// このPoolが所有する認証済みUser Scopeです。
    private let userScopeID: UUID

    /// Repositoryを検査済みPoolへ固定します。
    /// - Parameters:
    ///   - databasePool: Migrationとscope検査済みPool。
    ///   - userScopeID: Poolが所有するUser Scope。
    init(databasePool: DatabasePool, userScopeID: UUID) {
        self.databasePool = databasePool
        self.userScopeID = userScopeID
    }

    /// 指定端末のActive候補を役割別に読みます。
    /// - Parameter scope: 認証済みUserと端末境界。
    /// - Returns: Active候補辞書。
    /// - Throws: scope不一致または読取失敗。
    func activeCandidates(in scope: LocalDeviceScope) throws -> [CommunicationRole: DefaultAdapterCandidate] {
        try validate(scope)
        do {
            return try databasePool.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT * FROM default_adapter_candidates
                    WHERE user_scope_id = ? AND local_device_scope_id = ? AND platform = ? AND is_active = 1
                    ORDER BY role
                    """,
                    arguments: scopeArguments(scope)
                )
                return try Dictionary(uniqueKeysWithValues: rows.map { row in
                    let candidate = try decodeCandidate(row, scope: scope)
                    return (candidate.role, candidate)
                })
            }
        } catch let error as ConnectionSettingsError {
            throw error
        } catch {
            throw ConnectionSettingsError.unavailable
        }
    }

    /// 候補を役割のActive既定値として冪等保存します。
    /// - Parameters:
    ///   - endpoint: 接続前Endpoint候補。
    ///   - role: 固定役割。
    ///   - scope: User・端末境界。
    ///   - now: 監査日時。
    /// - Returns: DB確定済み候補。
    /// - Throws: Endpoint重複、scope不一致、DB失敗。
    func setDefault(
        endpoint: ConnectionEndpointCandidate,
        role: CommunicationRole,
        in scope: LocalDeviceScope,
        now: Date
    ) throws -> DefaultAdapterCandidate {
        try validate(scope)
        let stamp = GRDBVehicleDateCodec.string(from: now)
        do {
            return try databasePool.write { database in
                if let existing = try activeRow(role: role, scope: scope, database: database) {
                    let decoded = try decodeCandidate(existing, scope: scope)
                    if decoded.endpoint == endpoint { return decoded }
                    try database.execute(
                        sql: """
                        UPDATE default_adapter_candidates
                        SET is_active = 0, revision = revision + 1, updated_at = ?
                        WHERE user_scope_id = ? AND local_device_scope_id = ? AND candidate_id = ? AND is_active = 1
                        """,
                        arguments: [stamp, scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), decoded.candidateID.uuidString.lowercased()]
                    )
                }
                let duplicate = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT 1 FROM default_adapter_candidates
                    WHERE user_scope_id = ? AND local_device_scope_id = ? AND endpoint_digest = ? AND is_active = 1
                    LIMIT 1
                    """,
                    arguments: [scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), endpoint.endpointDigest]
                )
                guard duplicate == nil else { throw ConnectionSettingsError.duplicateRoleCandidate }

                let candidateID = UUID()
                try database.execute(
                    sql: """
                    INSERT INTO default_adapter_candidates
                      (user_scope_id, local_device_scope_id, platform, candidate_id, role, endpoint_digest, display_name, transport_kind, is_active, revision, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?)
                    """,
                    arguments: [
                        scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), scope.platform.rawValue,
                        candidateID.uuidString.lowercased(), role.rawValue, endpoint.endpointDigest, endpoint.displayName, endpoint.transportKind.rawValue,
                        stamp, stamp,
                    ]
                )
                guard let row = try Row.fetchOne(
                    database,
                    sql: "SELECT * FROM default_adapter_candidates WHERE user_scope_id = ? AND local_device_scope_id = ? AND candidate_id = ?",
                    arguments: [scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), candidateID.uuidString.lowercased()]
                ) else { throw ConnectionSettingsError.unavailable }
                return try decodeCandidate(row, scope: scope)
            }
        } catch let error as ConnectionSettingsError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw ConnectionSettingsError.duplicateRoleCandidate
        } catch {
            throw ConnectionSettingsError.unavailable
        }
    }

    /// 対象役割だけを解除し、履歴を保持します。
    /// - Parameters:
    ///   - role: 解除対象役割。
    ///   - scope: User・端末境界。
    ///   - now: 監査日時。
    /// - Throws: scope不一致またはDB失敗。
    func clearDefault(role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws {
        try validate(scope)
        let stamp = GRDBVehicleDateCodec.string(from: now)
        do {
            try databasePool.write { database in
                guard let row = try activeRow(role: role, scope: scope, database: database) else { return }
                let candidate = try decodeCandidate(row, scope: scope)
                try database.execute(
                    sql: """
                    UPDATE default_adapter_candidates
                    SET is_active = 0, revision = revision + 1, updated_at = ?
                    WHERE user_scope_id = ? AND local_device_scope_id = ? AND candidate_id = ? AND is_active = 1
                    """,
                    arguments: [stamp, scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), candidate.candidateID.uuidString.lowercased()]
                )
            }
        } catch let error as ConnectionSettingsError {
            throw error
        } catch {
            throw ConnectionSettingsError.unavailable
        }
    }

    /// 確認済みIdentity bindingを読みます。
    /// - Parameters:
    ///   - candidateID: 候補ID。
    ///   - scope: User・端末境界。
    /// - Returns: binding。未確認なら`nil`。
    /// - Throws: scope不一致またはDB失敗。
    func verifiedBinding(candidateID: UUID, in scope: LocalDeviceScope) throws -> VerifiedAdapterBinding? {
        try validate(scope)
        do {
            return try databasePool.read { database in
                guard let row = try Row.fetchOne(
                    database,
                    sql: """
                    SELECT * FROM verified_adapter_bindings
                    WHERE user_scope_id = ? AND local_device_scope_id = ? AND candidate_id = ?
                    """,
                    arguments: [scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), candidateID.uuidString.lowercased()]
                ) else { return nil }
                return try decodeBinding(row, scope: scope)
            }
        } catch let error as ConnectionSettingsError {
            throw error
        } catch {
            throw ConnectionSettingsError.unavailable
        }
    }

    /// 確認済みIdentity bindingを監査行として冪等保存します。
    /// - Parameter binding: 保存する確認済みbinding。
    /// - Throws: scope不一致、別bindingとの衝突、DB失敗。
    func saveVerifiedBinding(_ binding: VerifiedAdapterBinding) throws {
        try validate(binding.scope)
        let digest = binding.adapterReferenceDigest
        let stamp = GRDBVehicleDateCodec.string(from: binding.verifiedAt)
        do {
            try databasePool.write { database in
                if let row = try Row.fetchOne(
                    database,
                    sql: "SELECT * FROM verified_adapter_bindings WHERE user_scope_id = ? AND local_device_scope_id = ? AND candidate_id = ?",
                    arguments: [binding.scope.userScopeID.uuidString.lowercased(), binding.scope.localDeviceScopeID.uuidString.lowercased(), binding.candidateID.uuidString.lowercased()]
                ) {
                    let existingDigest: Data = row["adapter_reference_digest"]
                    guard existingDigest == digest else { throw ConnectionSettingsError.staleRevision }
                    return
                }
                try database.execute(
                    sql: """
                    INSERT INTO verified_adapter_bindings
                      (user_scope_id, local_device_scope_id, binding_id, candidate_id, adapter_reference_digest, verification_version, verified_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        binding.scope.userScopeID.uuidString.lowercased(), binding.scope.localDeviceScopeID.uuidString.lowercased(),
                        binding.bindingID.uuidString.lowercased(), binding.candidateID.uuidString.lowercased(), digest,
                        binding.verificationVersion, stamp,
                    ]
                )
            }
        } catch let error as ConnectionSettingsError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw ConnectionSettingsError.duplicateRoleCandidate
        } catch {
            throw ConnectionSettingsError.unavailable
        }
    }

    /// RepositoryのUser Scopeと要求scopeを照合します。
    /// - Parameter scope: 要求scope。
    /// - Throws: User Scope不一致。
    private func validate(_ scope: LocalDeviceScope) throws {
        guard scope.userScopeID == userScopeID else { throw ConnectionSettingsError.scopeMismatch }
    }

    /// roleのActive行を返します。
    /// - Parameters:
    ///   - role: 対象役割。
    ///   - scope: User・端末境界。
    ///   - database: 現在transactionのDatabase。
    /// - Returns: Active行。未設定なら`nil`。
    private func activeRow(role: CommunicationRole, scope: LocalDeviceScope, database: Database) throws -> Row? {
        try Row.fetchOne(
            database,
            sql: """
            SELECT * FROM default_adapter_candidates
            WHERE user_scope_id = ? AND local_device_scope_id = ? AND platform = ? AND role = ? AND is_active = 1
            """,
            arguments: scopeArguments(scope) + [role.rawValue]
        )
    }

    /// SQL引数用のscope値を返します。
    /// - Parameter scope: User・端末境界。
    /// - Returns: user、device、platform順の引数。
    private func scopeArguments(_ scope: LocalDeviceScope) -> StatementArguments {
        [scope.userScopeID.uuidString.lowercased(), scope.localDeviceScopeID.uuidString.lowercased(), scope.platform.rawValue]
    }

    /// GRDB RowをDomain候補へ変換します。
    /// - Parameters:
    ///   - row: 物理行。
    ///   - scope: 検査済みscope。
    /// - Returns: Domain候補。
    /// - Throws: 不正な永続値。
    private func decodeCandidate(_ row: Row, scope: LocalDeviceScope) throws -> DefaultAdapterCandidate {
        guard let candidateID = UUID(uuidString: row["candidate_id"]),
              let role = CommunicationRole(rawValue: row["role"]),
              let kind = TransportEndpoint.Kind(rawValue: row["transport_kind"]),
              let createdAt = GRDBVehicleDateCodec.date(from: row["created_at"]),
              let updatedAt = GRDBVehicleDateCodec.date(from: row["updated_at"]) else {
            throw ConnectionSettingsError.unavailable
        }
        let endpoint = try ConnectionEndpointCandidate(endpointDigest: row["endpoint_digest"], displayName: row["display_name"], transportKind: kind)
        return .init(candidateID: candidateID, scope: scope, role: role, endpoint: endpoint, revision: row["revision"], createdAt: createdAt, updatedAt: updatedAt)
    }

    /// GRDB Rowを確認済みbindingへ変換します。
    /// - Parameters:
    ///   - row: 物理行。
    ///   - scope: 検査済みscope。
    /// - Returns: Domain binding。
    /// - Throws: 不正な永続値。
    private func decodeBinding(_ row: Row, scope: LocalDeviceScope) throws -> VerifiedAdapterBinding {
        guard let bindingID = UUID(uuidString: row["binding_id"]),
              let candidateID = UUID(uuidString: row["candidate_id"]),
              let verifiedAt = GRDBVehicleDateCodec.date(from: row["verified_at"]) else {
            throw ConnectionSettingsError.unavailable
        }
        let digest: Data = row["adapter_reference_digest"]
        return try .init(bindingID: bindingID, candidateID: candidateID, scope: scope, adapterReferenceDigest: digest, verificationVersion: row["verification_version"], verifiedAt: verifiedAt)
    }
}
