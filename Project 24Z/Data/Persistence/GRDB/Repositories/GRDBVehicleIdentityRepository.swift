import Foundation
import GRDB

/// Vehicle Identity aggregateをscope専用GRDB transactionで永続化します。
final class GRDBVehicleIdentityRepository: VehicleIdentityRepository {
    private let databasePool: DatabasePool
    private let userScopeID: UUID
    private let scopeString: String

    /// 検査済みscope専用Poolを受け取ります。
    /// - Parameters:
    ///   - databasePool: `GRDBVehicleIdentityStore`が起動時検査したPool。
    ///   - userScopeID: Pool内の唯一のuser scope UUID。
    init(databasePool: DatabasePool, userScopeID: UUID) {
        self.databasePool = databasePool
        self.userScopeID = userScopeID
        scopeString = userScopeID.uuidString.lowercased()
    }

    /// activeとarchivedを混在させず車両一覧を取得します。
    /// - Parameter lifecycle: 取得するライフサイクル状態。
    /// - Returns: 指定状態の車両だけを更新日時降順で返します。
    /// - Throws: DB利用不能または不正レコード時の安定エラー。
    func fetchVehicles(lifecycle: VehicleIdentity.Lifecycle) throws -> [VehicleIdentity] {
        do {
            return try databasePool.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: "SELECT * FROM vehicles WHERE user_scope_id = ? AND lifecycle_state = ? ORDER BY updated_at DESC, vehicle_id",
                    arguments: [scopeString, lifecycle.rawValue]
                )
                return try rows.map(makeVehicle)
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// Digestに一致する候補を一意に取得します。
    /// - Parameters:
    ///   - kind: 識別子種別。
    ///   - lookupDigest: 32 byte keyed Digest。
    /// - Returns: 一致しなければnil、一意なら車両。
    /// - Throws: Digest形状、複数一致、DB利用不能時の安定エラー。
    func findCandidate(
        kind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data
    ) throws -> VehicleIdentity? {
        guard lookupDigest.count == 32 else { throw VehiclePersistenceError.invalidRequest }
        do {
            return try databasePool.read { database in
                try findCandidate(database: database, kind: kind, digest: lookupDigest)
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// 登録要求を新規、active一致、archived一致の一transactionへ収束させます。
    /// - Parameter request: 暗号・Digest準備済みの最終Snapshot要求。
    /// - Returns: active登録結果または明示復元待ち結果。
    /// - Throws: 入力不正、Unique競合、冪等性差異、DB利用不能時の安定エラー。
    func register(_ request: VehicleRegistrationRequest) throws -> VehicleRegistrationResult {
        try validateRegistrationRequest(request)
        do {
            return try databasePool.write { database in
                try verifyScopeAndDigestVersion(database: database, identifiers: request.identifiers)
                let candidates = try request.identifiers.map {
                    try findCandidate(database: database, kind: $0.kind, digest: $0.lookupDigest)
                }
                let matched = candidates.compactMap { $0 }
                let matchedIDs = Set(matched.map(\.vehicleID))
                guard matchedIDs.count <= 1 else { throw VehiclePersistenceError.conflict }
                guard matched.isEmpty || matched.count == candidates.count else {
                    throw VehiclePersistenceError.conflict
                }

                let vehicleID = matched.first?.vehicleID ?? request.proposedVehicleID
                if try scanExists(database: database, obdConnectionID: request.scan.obdConnectionID) {
                    guard try snapshotMatches(
                        database: database,
                        snapshot: request.scan,
                        vehicleID: vehicleID,
                        deviceID: request.deviceID,
                        recordedAt: request.recordedAt
                    ) else {
                        throw VehiclePersistenceError.idempotencyConflict
                    }
                    let persisted = try requireVehicle(database: database, vehicleID: vehicleID)
                    return makeRegistrationResult(vehicle: persisted)
                }

                let isNewVehicle = matched.isEmpty
                if isNewVehicle {
                    try insertVehicle(database: database, request: request)
                }
                try insertSnapshot(
                    database: database,
                    snapshot: request.scan,
                    vehicleID: vehicleID,
                    deviceID: request.deviceID,
                    recordedAt: request.recordedAt
                )
                if isNewVehicle {
                    try insertIdentifiers(
                        database: database,
                        identifiers: request.identifiers,
                        vehicleID: vehicleID,
                        sourceScanID: request.scan.scanID,
                        deviceID: request.deviceID,
                        recordedAt: request.recordedAt
                    )
                }
                try verifyPersistedSnapshotCounts(database: database, snapshot: request.scan)
                guard try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty else {
                    throw VehiclePersistenceError.unavailable
                }
                let persisted = try requireVehicle(database: database, vehicleID: vehicleID)
                return makeRegistrationResult(vehicle: persisted)
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw VehiclePersistenceError.conflict
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// valid以外の終端Snapshotを一接続一件で追記します。
    /// - Parameters:
    ///   - snapshot: 終端Snapshot。
    ///   - vehicleID: 確実な登録車両。未登録ならnil。
    ///   - deviceID: 記録端末UUID。
    ///   - recordedAt: DB記録日時。
    /// - Throws: valid入力、重複差異、制約違反、利用不能時の安定エラー。
    func appendTerminalScan(
        _ snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws {
        try validateSnapshot(snapshot)
        guard snapshot.identityValidationState != .valid else {
            throw VehiclePersistenceError.invalidRequest
        }
        do {
            try databasePool.write { database in
                try verifyScope(database: database)
                if try scanExists(database: database, obdConnectionID: snapshot.obdConnectionID) {
                    guard try snapshotMatches(
                        database: database,
                        snapshot: snapshot,
                        vehicleID: vehicleID,
                        deviceID: deviceID,
                        recordedAt: recordedAt
                    ) else {
                        throw VehiclePersistenceError.idempotencyConflict
                    }
                    return
                }
                if let vehicleID {
                    _ = try requireVehicle(database: database, vehicleID: vehicleID)
                }
                try insertSnapshot(
                    database: database,
                    snapshot: snapshot,
                    vehicleID: vehicleID,
                    deviceID: deviceID,
                    recordedAt: recordedAt
                )
                try verifyPersistedSnapshotCounts(database: database, snapshot: snapshot)
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw VehiclePersistenceError.conflict
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// active車両を期待Revisionでアーカイブして再読込します。
    /// - Parameters:
    ///   - vehicleID: 対象車両UUID。
    ///   - expectedLifecycleRevision: 確認済みRevision。
    ///   - deviceID: 更新端末UUID。
    ///   - updatedAt: 更新日時。
    /// - Returns: 読戻し検証済みarchived車両。
    /// - Throws: 競合または利用不能時の安定エラー。
    func archiveVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        guard expectedLifecycleRevision >= 1 else { throw VehiclePersistenceError.invalidRequest }
        do {
            return try databasePool.write { database in
                try verifyScope(database: database)
                let timestamp = GRDBVehicleDateCodec.string(from: updatedAt)
                try database.execute(
                    sql: """
                    UPDATE vehicles
                    SET lifecycle_state = 'archived', archived_at = ?,
                        lifecycle_revision = lifecycle_revision + 1,
                        lifecycle_updated_at = ?, lifecycle_updated_by_device_id = ?,
                        record_revision = record_revision + 1,
                        updated_at = ?, updated_by_device_id = ?
                    WHERE user_scope_id = ? AND vehicle_id = ?
                      AND lifecycle_state = 'active' AND lifecycle_revision = ?
                    """,
                    arguments: [timestamp, timestamp, uuidString(deviceID), timestamp, uuidString(deviceID), scopeString, uuidString(vehicleID), expectedLifecycleRevision]
                )
                guard database.changesCount == 1 else { throw VehiclePersistenceError.conflict }
                let archived = try requireVehicle(database: database, vehicleID: vehicleID)
                guard archived.lifecycle == .archived,
                      archived.lifecycleRevision == expectedLifecycleRevision + 1 else {
                    throw VehiclePersistenceError.conflict
                }
                return archived
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw VehiclePersistenceError.conflict
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// archived車両を期待RevisionとIdentifier根拠で復元して再読込します。
    /// - Parameters:
    ///   - vehicleID: 復元対象車両UUID。
    ///   - expectedLifecycleRevision: 確認済みRevision。
    ///   - identifierKind: 根拠識別子種別。
    ///   - lookupDigest: 根拠Digest。
    ///   - deviceID: 更新端末UUID。
    ///   - updatedAt: 更新日時。
    /// - Returns: 読戻し検証済みactive車両。
    /// - Throws: 競合、根拠不一致、利用不能時の安定エラー。
    func restoreArchivedVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        identifierKind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        guard expectedLifecycleRevision >= 1, lookupDigest.count == 32 else {
            throw VehiclePersistenceError.invalidRequest
        }
        do {
            return try databasePool.write { database in
                try verifyScope(database: database)
                guard let candidate = try findCandidate(
                    database: database,
                    kind: identifierKind,
                    digest: lookupDigest
                ), candidate.vehicleID == vehicleID,
                   candidate.lifecycle == .archived,
                   candidate.lifecycleRevision == expectedLifecycleRevision else {
                    throw VehiclePersistenceError.conflict
                }
                let timestamp = GRDBVehicleDateCodec.string(from: updatedAt)
                try database.execute(
                    sql: """
                    UPDATE vehicles
                    SET lifecycle_state = 'active', archived_at = NULL,
                        lifecycle_revision = lifecycle_revision + 1,
                        lifecycle_updated_at = ?, lifecycle_updated_by_device_id = ?,
                        record_revision = record_revision + 1,
                        updated_at = ?, updated_by_device_id = ?
                    WHERE user_scope_id = ? AND vehicle_id = ?
                      AND lifecycle_state = 'archived' AND lifecycle_revision = ?
                    """,
                    arguments: [timestamp, uuidString(deviceID), timestamp, uuidString(deviceID), scopeString, uuidString(vehicleID), expectedLifecycleRevision]
                )
                guard database.changesCount == 1 else { throw VehiclePersistenceError.conflict }
                let restored = try requireVehicle(database: database, vehicleID: vehicleID)
                guard restored.lifecycle == .active,
                      restored.lifecycleRevision == expectedLifecycleRevision + 1,
                      let reread = try findCandidate(database: database, kind: identifierKind, digest: lookupDigest),
                      reread.vehicleID == vehicleID else {
                    throw VehiclePersistenceError.conflict
                }
                return restored
            }
        } catch let error as VehiclePersistenceError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw VehiclePersistenceError.conflict
        } catch {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// 登録要求の構造、暗号文形状、valid境界を検証します。
    /// - Parameter request: 検証する登録要求。
    /// - Throws: 設計契約を満たさない場合`invalidRequest`。
    private func validateRegistrationRequest(_ request: VehicleRegistrationRequest) throws {
        guard !request.identifiers.isEmpty,
              request.scan.status == .completed,
              request.scan.identityValidationState == .valid,
              !request.scan.observations.isEmpty else {
            throw VehiclePersistenceError.invalidRequest
        }
        if let displayName = request.encryptedDisplayName {
            try validateEncryptedValue(displayName)
        }
        var kinds = Set<VehicleIdentifierEvidence.Kind>()
        for identifier in request.identifiers {
            guard kinds.insert(identifier.kind).inserted,
                  identifier.lookupDigest.count == 32,
                  identifier.digestKeyVersion >= 1 else {
                throw VehiclePersistenceError.invalidRequest
            }
            try validateEncryptedValue(identifier.encryptedNormalizedValue)
        }
        try validateSnapshot(request.scan)
    }

    /// 一接続Snapshotの終端性と子要素の一意性を検証します。
    /// - Parameter snapshot: 検証するSnapshot。
    /// - Throws: 終端条件または暗号済み値が不正なら`invalidRequest`。
    private func validateSnapshot(_ snapshot: VehicleIdentificationScanSnapshot) throws {
        guard snapshot.startedAt <= snapshot.finishedAt,
              (1...64).contains(snapshot.transportKind.count),
              (1...64).contains(snapshot.diagnosticProtocolKind.count),
              (1...128).contains(snapshot.adapterReferenceID.count),
              (1...64).contains(snapshot.decoderVersion.count),
              (1...64).contains(snapshot.normalizationVersion.count) else {
            throw VehiclePersistenceError.invalidRequest
        }
        if snapshot.status == .completed {
            guard snapshot.terminationReasonCode == nil else { throw VehiclePersistenceError.invalidRequest }
        } else {
            guard let reason = snapshot.terminationReasonCode, (1...64).contains(reason.count) else {
                throw VehiclePersistenceError.invalidRequest
            }
        }
        var observationOrdinals = Set<Int>()
        var observationIDs = Set<UUID>()
        for observation in snapshot.observations {
            guard observation.ordinal >= 0,
                  observationOrdinals.insert(observation.ordinal).inserted,
                  observationIDs.insert(observation.observationID).inserted,
                  !observation.responderAddress.isEmpty else {
                throw VehiclePersistenceError.invalidRequest
            }
            var valueKeys = Set<String>()
            var valueIDs = Set<UUID>()
            for value in observation.values {
                let key = "\(value.infoTypeCode)-\(value.occurrenceOrdinal)"
                guard value.occurrenceOrdinal >= 0,
                      valueKeys.insert(key).inserted,
                      valueIDs.insert(value.valueID).inserted else {
                    throw VehiclePersistenceError.invalidRequest
                }
                if value.decodeState == .decoded {
                    guard let decoded = value.encryptedDecodedValue else {
                        throw VehiclePersistenceError.invalidRequest
                    }
                    try validateEncryptedValue(decoded)
                } else if value.encryptedDecodedValue != nil {
                    throw VehiclePersistenceError.invalidRequest
                }
                try validateEncryptedValue(value.encryptedRawResponse)
            }
        }
    }

    /// 認証付き暗号combined boxの最低形状と鍵Versionを検証します。
    /// - Parameter value: 暗号済み値。
    /// - Throws: 形状不正なら`invalidRequest`。
    private func validateEncryptedValue(_ value: EncryptedVehicleValue) throws {
        guard value.ciphertext.count >= 29, value.keyVersion >= 1 else {
            throw VehiclePersistenceError.invalidRequest
        }
    }

    /// DB scopeだけをtransaction内で再確認します。
    /// - Parameter database: 現在のGRDB write接続。
    /// - Throws: scope不一致なら`scopeMismatch`。
    private func verifyScope(database: Database) throws {
        let scope = try String.fetchOne(database, sql: "SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1")
        guard scope == scopeString else { throw VehiclePersistenceError.scopeMismatch }
    }

    /// DB scopeと全IdentifierのDigest鍵Versionを再確認します。
    /// - Parameters:
    ///   - database: 現在のGRDB write接続。
    ///   - identifiers: 登録予定Identifier。
    /// - Throws: scopeまたはVersion不一致時の安定エラー。
    private func verifyScopeAndDigestVersion(
        database: Database,
        identifiers: [VehicleIdentifierEvidence]
    ) throws {
        try verifyScope(database: database)
        guard let version = try Int.fetchOne(
            database,
            sql: "SELECT active_digest_key_version FROM database_scope WHERE scope_row_id = 1"
        ), identifiers.allSatisfy({ $0.digestKeyVersion == version }) else {
            throw VehiclePersistenceError.scopeMismatch
        }
    }

    /// kindとDigestから最大2件を読み、一意な車両へ変換します。
    /// - Parameters:
    ///   - database: 読取接続。
    ///   - kind: Identifier種別。
    ///   - digest: 32 byte Digest。
    /// - Returns: 一致なしならnil、一意なら車両。
    /// - Throws: 複数一致またはレコード不正時のエラー。
    private func findCandidate(
        database: Database,
        kind: VehicleIdentifierEvidence.Kind,
        digest: Data
    ) throws -> VehicleIdentity? {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT v.* FROM vehicle_identifiers i
            JOIN vehicles v ON v.user_scope_id = i.user_scope_id AND v.vehicle_id = i.vehicle_id
            WHERE i.user_scope_id = ? AND i.identifier_kind = ? AND i.lookup_digest = ?
            LIMIT 2
            """,
            arguments: [scopeString, kind.rawValue, digest]
        )
        guard rows.count <= 1 else { throw VehiclePersistenceError.unavailable }
        return try rows.first.map(makeVehicle)
    }

    /// 新規Vehicle行を初期Revisionで追加します。
    /// - Parameters:
    ///   - database: write接続。
    ///   - request: 新規車両登録要求。
    /// - Throws: SQL制約エラー。
    private func insertVehicle(database: Database, request: VehicleRegistrationRequest) throws {
        let timestamp = GRDBVehicleDateCodec.string(from: request.recordedAt)
        let display = request.encryptedDisplayName
        let displayRevision = display == nil ? 0 : 1
        try database.execute(
            sql: """
            INSERT INTO vehicles (
              user_scope_id, vehicle_id, display_name_ciphertext, display_name_key_version,
              lifecycle_state, record_revision, display_name_revision,
              display_name_updated_at, display_name_updated_by_device_id,
              lifecycle_revision, lifecycle_updated_at, lifecycle_updated_by_device_id,
              archived_at, created_at, created_by_device_id, updated_at, updated_by_device_id
            ) VALUES (?, ?, ?, ?, 'active', 1, ?, ?, ?, 1, ?, ?, NULL, ?, ?, ?, ?)
            """,
            arguments: [
                scopeString, uuidString(request.proposedVehicleID), display?.ciphertext,
                display?.keyVersion, displayRevision, display == nil ? nil : timestamp,
                display == nil ? nil : uuidString(request.deviceID), timestamp,
                uuidString(request.deviceID), timestamp, uuidString(request.deviceID),
                timestamp, uuidString(request.deviceID)
            ]
        )
    }

    /// 親から子の順に最終Snapshot全体を追加します。
    /// - Parameters:
    ///   - database: write接続。
    ///   - snapshot: 終端Snapshot。
    ///   - vehicleID: 関連車両またはnil。
    ///   - deviceID: 記録端末UUID。
    ///   - recordedAt: 記録日時。
    /// - Throws: 必須行または制約違反。
    private func insertSnapshot(
        database: Database,
        snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws {
        let recorded = GRDBVehicleDateCodec.string(from: recordedAt)
        try database.execute(
            sql: """
            INSERT INTO vehicle_identification_scans (
              user_scope_id, scan_id, vehicle_id, obd_connection_id, transport_kind,
              diagnostic_protocol_kind, adapter_reference_id, decoder_version,
              normalization_version, scan_status, decode_state, identity_validation_state,
              termination_reason_code, started_at, finished_at, revision, created_at,
              created_by_device_id, updated_at, updated_by_device_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
            """,
            arguments: [
                scopeString, uuidString(snapshot.scanID), vehicleID.map(uuidString),
                uuidString(snapshot.obdConnectionID), snapshot.transportKind,
                snapshot.diagnosticProtocolKind, snapshot.adapterReferenceID,
                snapshot.decoderVersion, snapshot.normalizationVersion, snapshot.status.rawValue,
                snapshot.decodeState.rawValue, snapshot.identityValidationState.rawValue,
                snapshot.terminationReasonCode, GRDBVehicleDateCodec.string(from: snapshot.startedAt),
                GRDBVehicleDateCodec.string(from: snapshot.finishedAt), recorded, uuidString(deviceID),
                recorded, uuidString(deviceID)
            ]
        )
        for observation in snapshot.observations {
            try database.execute(
                sql: """
                INSERT INTO ecu_observations (
                  user_scope_id, ecu_observation_id, scan_id, observation_ordinal,
                  responder_address_format, responder_address, revision, created_at,
                  created_by_device_id, updated_at, updated_by_device_id
                ) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                """,
                arguments: [scopeString, uuidString(observation.observationID), uuidString(snapshot.scanID), observation.ordinal, observation.addressFormat.rawValue, observation.responderAddress, recorded, uuidString(deviceID), recorded, uuidString(deviceID)]
            )
            for value in observation.values {
                try database.execute(
                    sql: """
                    INSERT INTO ecu_identification_values (
                      user_scope_id, identification_value_id, ecu_observation_id,
                      info_type_code, occurrence_ordinal, value_kind, decode_state,
                      validation_state, decoded_value_ciphertext, decoded_value_key_version,
                      raw_response_ciphertext, raw_response_key_version, revision, created_at,
                      created_by_device_id, updated_at, updated_by_device_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                    """,
                    arguments: [scopeString, uuidString(value.valueID), uuidString(observation.observationID), Int(value.infoTypeCode), value.occurrenceOrdinal, value.valueKind.rawValue, value.decodeState.rawValue, value.validationState.rawValue, value.encryptedDecodedValue?.ciphertext, value.encryptedDecodedValue?.keyVersion, value.encryptedRawResponse.ciphertext, value.encryptedRawResponse.keyVersion, recorded, uuidString(deviceID), recorded, uuidString(deviceID)]
                )
            }
        }
    }

    /// 新規Vehicleだけに登録根拠Identifierを追加します。
    /// - Parameters:
    ///   - database: write接続。
    ///   - identifiers: 準備済み識別子。
    ///   - vehicleID: 新規Vehicle UUID。
    ///   - sourceScanID: completedかつvalidな根拠Scan UUID。
    ///   - deviceID: 記録端末UUID。
    ///   - recordedAt: 記録日時。
    /// - Throws: Unique、FK、Trigger制約違反。
    private func insertIdentifiers(
        database: Database,
        identifiers: [VehicleIdentifierEvidence],
        vehicleID: UUID,
        sourceScanID: UUID,
        deviceID: UUID,
        recordedAt: Date
    ) throws {
        let timestamp = GRDBVehicleDateCodec.string(from: recordedAt)
        for identifier in identifiers {
            try database.execute(
                sql: """
                INSERT INTO vehicle_identifiers (
                  user_scope_id, identifier_id, vehicle_id, identifier_kind,
                  normalized_value_ciphertext, encryption_key_version, lookup_digest,
                  digest_key_version, source_scan_id, revision, created_at,
                  created_by_device_id, updated_at, updated_by_device_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
                """,
                arguments: [scopeString, uuidString(identifier.identifierID), uuidString(vehicleID), identifier.kind.rawValue, identifier.encryptedNormalizedValue.ciphertext, identifier.encryptedNormalizedValue.keyVersion, identifier.lookupDigest, identifier.digestKeyVersion, uuidString(sourceScanID), timestamp, uuidString(deviceID), timestamp, uuidString(deviceID)]
            )
        }
    }

    /// Snapshotの親子件数をtransaction中に読戻して検証します。
    /// - Parameters:
    ///   - database: write接続。
    ///   - snapshot: 期待件数を持つSnapshot。
    /// - Throws: 件数が一致しない場合`unavailable`。
    private func verifyPersistedSnapshotCounts(
        database: Database,
        snapshot: VehicleIdentificationScanSnapshot
    ) throws {
        let observationCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM ecu_observations WHERE user_scope_id = ? AND scan_id = ?",
            arguments: [scopeString, uuidString(snapshot.scanID)]
        )
        let valueCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM ecu_identification_values v
            JOIN ecu_observations o ON o.user_scope_id = v.user_scope_id AND o.ecu_observation_id = v.ecu_observation_id
            WHERE o.user_scope_id = ? AND o.scan_id = ?
            """,
            arguments: [scopeString, uuidString(snapshot.scanID)]
        )
        guard observationCount == snapshot.observations.count,
              valueCount == snapshot.observations.reduce(0, { $0 + $1.values.count }) else {
            throw VehiclePersistenceError.unavailable
        }
    }

    /// connection UUIDに終端Scanが既にあるか確認します。
    /// - Parameters:
    ///   - database: 読取接続。
    ///   - obdConnectionID: 一接続UUID。
    /// - Returns: 既存行があればtrue。
    private func scanExists(database: Database, obdConnectionID: UUID) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: "SELECT EXISTS(SELECT 1 FROM vehicle_identification_scans WHERE user_scope_id = ? AND obd_connection_id = ?)",
            arguments: [scopeString, uuidString(obdConnectionID)]
        ) ?? false
    }

    /// commit結果不明時に既存Snapshotの全列と全子行を比較します。
    /// - Parameters:
    ///   - database: 読取接続。
    ///   - snapshot: 再試行された最終Snapshot。
    ///   - vehicleID: 期待する所属車両またはnil。
    ///   - deviceID: 初回記録端末UUID。
    ///   - recordedAt: 初回記録日時。
    /// - Returns: 暗号文を含む全永続内容が一致する場合だけtrue。
    private func snapshotMatches(
        database: Database,
        snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws -> Bool {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM vehicle_identification_scans WHERE user_scope_id = ? AND obd_connection_id = ?",
            arguments: [scopeString, uuidString(snapshot.obdConnectionID)]
        ) else { return false }
        let expectedVehicle = vehicleID.map(uuidString)
        guard (row["scan_id"] as String) == uuidString(snapshot.scanID),
              (row["vehicle_id"] as String?) == expectedVehicle,
              (row["transport_kind"] as String) == snapshot.transportKind,
              (row["diagnostic_protocol_kind"] as String) == snapshot.diagnosticProtocolKind,
              (row["adapter_reference_id"] as String) == snapshot.adapterReferenceID,
              (row["decoder_version"] as String) == snapshot.decoderVersion,
              (row["normalization_version"] as String) == snapshot.normalizationVersion,
              (row["scan_status"] as String) == snapshot.status.rawValue,
              (row["decode_state"] as String) == snapshot.decodeState.rawValue,
              (row["identity_validation_state"] as String) == snapshot.identityValidationState.rawValue,
              (row["termination_reason_code"] as String?) == snapshot.terminationReasonCode,
              (row["started_at"] as String) == GRDBVehicleDateCodec.string(from: snapshot.startedAt),
              (row["finished_at"] as String) == GRDBVehicleDateCodec.string(from: snapshot.finishedAt),
              (row["created_at"] as String) == GRDBVehicleDateCodec.string(from: recordedAt),
              (row["created_by_device_id"] as String) == uuidString(deviceID) else { return false }

        let observationRows = try Row.fetchAll(
            database,
            sql: "SELECT * FROM ecu_observations WHERE user_scope_id = ? AND scan_id = ? ORDER BY observation_ordinal",
            arguments: [scopeString, uuidString(snapshot.scanID)]
        )
        guard observationRows.count == snapshot.observations.count else { return false }
        for (observationRow, observation) in zip(observationRows, snapshot.observations.sorted(by: { $0.ordinal < $1.ordinal })) {
            guard (observationRow["ecu_observation_id"] as String) == uuidString(observation.observationID),
                  (observationRow["observation_ordinal"] as Int) == observation.ordinal,
                  (observationRow["responder_address_format"] as String) == observation.addressFormat.rawValue,
                  (observationRow["responder_address"] as Data) == observation.responderAddress else { return false }
            let valueRows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM ecu_identification_values WHERE user_scope_id = ? AND ecu_observation_id = ? ORDER BY info_type_code, occurrence_ordinal",
                arguments: [scopeString, uuidString(observation.observationID)]
            )
            let values = observation.values.sorted {
                ($0.infoTypeCode, $0.occurrenceOrdinal) < ($1.infoTypeCode, $1.occurrenceOrdinal)
            }
            guard valueRows.count == values.count else { return false }
            for (valueRow, value) in zip(valueRows, values) {
                guard (valueRow["identification_value_id"] as String) == uuidString(value.valueID),
                      (valueRow["info_type_code"] as Int) == Int(value.infoTypeCode),
                      (valueRow["occurrence_ordinal"] as Int) == value.occurrenceOrdinal,
                      (valueRow["value_kind"] as String) == value.valueKind.rawValue,
                      (valueRow["decode_state"] as String) == value.decodeState.rawValue,
                      (valueRow["validation_state"] as String) == value.validationState.rawValue,
                      (valueRow["decoded_value_ciphertext"] as Data?) == value.encryptedDecodedValue?.ciphertext,
                      (valueRow["decoded_value_key_version"] as Int?) == value.encryptedDecodedValue?.keyVersion,
                      (valueRow["raw_response_ciphertext"] as Data) == value.encryptedRawResponse.ciphertext,
                      (valueRow["raw_response_key_version"] as Int) == value.encryptedRawResponse.keyVersion else { return false }
            }
        }
        return true
    }

    /// 車両行を必須で読戻します。
    /// - Parameters:
    ///   - database: 読取接続。
    ///   - vehicleID: 内部車両UUID。
    /// - Returns: Domain車両。
    /// - Throws: 行欠損または不正時の安定エラー。
    private func requireVehicle(database: Database, vehicleID: UUID) throws -> VehicleIdentity {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM vehicles WHERE user_scope_id = ? AND vehicle_id = ?",
            arguments: [scopeString, uuidString(vehicleID)]
        ) else { throw VehiclePersistenceError.conflict }
        return try makeVehicle(row)
    }

    /// GRDB Rowを永続化方式非依存のVehicleへ変換します。
    /// - Parameter row: `vehicles`の一行。
    /// - Returns: Domain車両。
    /// - Throws: UUID、日時、enumが不正なら`unavailable`。
    private func makeVehicle(_ row: Row) throws -> VehicleIdentity {
        guard let scopeID = strictUUID(row["user_scope_id"] as String),
              scopeID == userScopeID,
              let vehicleID = strictUUID(row["vehicle_id"] as String),
              let lifecycle = VehicleIdentity.Lifecycle(rawValue: row["lifecycle_state"] as String),
              let createdAt = GRDBVehicleDateCodec.date(from: row["created_at"] as String),
              let updatedAt = GRDBVehicleDateCodec.date(from: row["updated_at"] as String) else {
            throw VehiclePersistenceError.unavailable
        }
        let ciphertext = row["display_name_ciphertext"] as Data?
        let keyVersion = row["display_name_key_version"] as Int?
        let display: EncryptedVehicleValue?
        if let ciphertext, let keyVersion {
            display = EncryptedVehicleValue(ciphertext: ciphertext, keyVersion: keyVersion)
        } else if ciphertext == nil, keyVersion == nil {
            display = nil
        } else {
            throw VehiclePersistenceError.unavailable
        }
        let archivedString = row["archived_at"] as String?
        let archivedAt = archivedString.flatMap(GRDBVehicleDateCodec.date)
        guard archivedString == nil || archivedAt != nil else { throw VehiclePersistenceError.unavailable }
        return VehicleIdentity(
            userScopeID: scopeID,
            vehicleID: vehicleID,
            encryptedDisplayName: display,
            lifecycle: lifecycle,
            recordRevision: row["record_revision"],
            displayNameRevision: row["display_name_revision"],
            lifecycleRevision: row["lifecycle_revision"],
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Lifecycleによりactive成功とarchived復元待ちを分離します。
    /// - Parameter vehicle: 読戻し済み車両。
    /// - Returns: 混在しない登録結果。
    private func makeRegistrationResult(vehicle: VehicleIdentity) -> VehicleRegistrationResult {
        switch vehicle.lifecycle {
        case .active: .registered(vehicle)
        case .archived: .archivedRestoreRequired(vehicle)
        }
    }

    /// UUIDをDB標準の小文字ハイフン形式へ変換します。
    /// - Parameter uuid: 変換するUUID。
    /// - Returns: 小文字ハイフン付き文字列。
    private func uuidString(_ uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    /// DB文字列をcanonical UUIDだけに限定して読戻します。
    /// - Parameter value: DB文字列。
    /// - Returns: canonical小文字形式ならUUID、それ以外はnil。
    private func strictUUID(_ value: String) -> UUID? {
        guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value else { return nil }
        return uuid
    }
}
