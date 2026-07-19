import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// v5の端末別・役割別候補保存と監査制約を検証します。
@Suite(.serialized)
struct GRDBDefaultAdapterRepositoryTests {
    /// Primary／Secondaryを分離保存し、同じEndpointのActive重複を拒否します。
    @Test
    func roleDefaultsAreDistinctAndIdempotent() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try requireStore(fixture)
        let repository = store.defaultAdapterRepository
        let scope = makeScope(deviceID: VehicleIdentityTestFixtures.deviceID)
        let primary = try candidate(byte: 1, name: "Primary")
        let secondary = try candidate(byte: 2, name: "Secondary")

        let saved = try repository.setDefault(endpoint: primary, role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt)
        let idempotent = try repository.setDefault(endpoint: primary, role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt)
        _ = try repository.setDefault(endpoint: secondary, role: .secondaryRawCAN, in: scope, now: VehicleIdentityTestFixtures.recordedAt)

        #expect(saved.candidateID == idempotent.candidateID)
        #expect(try repository.activeCandidates(in: scope).count == 2)
        #expect(throws: ConnectionSettingsError.duplicateRoleCandidate) {
            try repository.setDefault(endpoint: primary, role: .secondaryRawCAN, in: scope, now: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(1))
        }
    }

    /// iPhone相当端末とMac相当端末の候補が相互に読めないことを検証します。
    @Test
    func localDeviceScopesDoNotSynchronize() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let repository = try requireStore(fixture).defaultAdapterRepository
        let phone = makeScope(deviceID: UUID(), platform: .iOS)
        let mac = makeScope(deviceID: UUID(), platform: .macOS)
        _ = try repository.setDefault(endpoint: candidate(byte: 3, name: "Phone"), role: .primaryOBD, in: phone, now: VehicleIdentityTestFixtures.recordedAt)

        #expect(try repository.activeCandidates(in: phone)[.primaryOBD]?.endpoint.displayName == "Phone")
        #expect(try repository.activeCandidates(in: mac).isEmpty)
    }

    /// 設定変更と解除が履歴行を削除せずActiveだけを切り替えることを検証します。
    @Test
    func changeAndClearPreserveHistory() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try requireStore(fixture)
        let repository = store.defaultAdapterRepository
        let scope = makeScope(deviceID: VehicleIdentityTestFixtures.deviceID)
        _ = try repository.setDefault(endpoint: candidate(byte: 4, name: "Old"), role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt)
        _ = try repository.setDefault(endpoint: candidate(byte: 5, name: "New"), role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(1))
        try repository.clearDefault(role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(2))

        #expect(try repository.activeCandidates(in: scope).isEmpty)
        let counts = try store.databasePool.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM default_adapter_candidates")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM default_adapter_candidates WHERE is_active = 1")!
            )
        }
        #expect(counts.0 == 2)
        #expect(counts.1 == 0)
    }

    /// 確認済みbindingだけを保存し、同じ物理参照の候補間重複を拒否します。
    @Test
    func verifiedBindingsAreImmutableAndDistinct() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let repository = try requireStore(fixture).defaultAdapterRepository
        let scope = makeScope(deviceID: VehicleIdentityTestFixtures.deviceID)
        let primary = try repository.setDefault(endpoint: candidate(byte: 6, name: "Primary"), role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt)
        let secondary = try repository.setDefault(endpoint: candidate(byte: 7, name: "Secondary"), role: .secondaryRawCAN, in: scope, now: VehicleIdentityTestFixtures.recordedAt)
        let referenceDigest = Data(repeating: 9, count: 32)
        let binding = try VerifiedAdapterBinding(bindingID: UUID(), candidateID: primary.candidateID, scope: scope, adapterReferenceDigest: referenceDigest, verificationVersion: "identity-v1", verifiedAt: VehicleIdentityTestFixtures.recordedAt)
        try repository.saveVerifiedBinding(binding)
        try repository.saveVerifiedBinding(binding)

        #expect(try repository.verifiedBinding(candidateID: primary.candidateID, in: scope) != nil)
        #expect(throws: ConnectionSettingsError.duplicateRoleCandidate) {
            try repository.saveVerifiedBinding(.init(bindingID: UUID(), candidateID: secondary.candidateID, scope: scope, adapterReferenceDigest: referenceDigest, verificationVersion: "identity-v1", verifiedAt: VehicleIdentityTestFixtures.recordedAt))
        }

        try repository.clearDefault(role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(1))
        let replacement = try repository.setDefault(endpoint: candidate(byte: 8, name: "Replacement"), role: .primaryOBD, in: scope, now: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(2))
        try repository.saveVerifiedBinding(.init(bindingID: UUID(), candidateID: replacement.candidateID, scope: scope, adapterReferenceDigest: referenceDigest, verificationVersion: "identity-v1", verifiedAt: VehicleIdentityTestFixtures.recordedAt.addingTimeInterval(2)))
        #expect(try repository.verifiedBinding(candidateID: replacement.candidateID, in: scope) != nil)
    }

    /// v5 tableがMigrationで作成されることを検証します。
    @Test
    func migrationCreatesConnectionSettingsTables() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try requireStore(fixture)
        let tables = try store.databasePool.read { database in
            try String.fetchAll(database, sql: "SELECT name FROM sqlite_schema WHERE type = 'table'")
        }
        #expect(tables.contains("default_adapter_candidates"))
        #expect(tables.contains("verified_adapter_bindings"))
    }

    /// v5 DDL後の失敗がschema全体をrollbackすることを検証します。
    @Test
    func migrationFailureRollsBackConnectionSettingsSchema() throws {
        let queue = try DatabaseQueue()
        try queue.write { database in
            try database.execute(sql: "CREATE TABLE database_scope(scope_row_id INTEGER PRIMARY KEY, user_scope_id TEXT NOT NULL)")
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("test_v5_rollback") { database in
            try database.execute(sql: ConnectionSettingsSchema.v5SQL)
            throw ConnectionSettingsError.unavailable
        }

        #expect(throws: ConnectionSettingsError.unavailable) { try migrator.migrate(queue) }
        #expect(try queue.read { try !$0.tableExists("default_adapter_candidates") })
        #expect(try queue.read { try !$0.tableExists("verified_adapter_bindings") })
    }

    /// 固定Digestの候補を作ります。
    /// - Parameters:
    ///   - byte: Digest fixture byte。
    ///   - name: 非機密表示名。
    /// - Returns: 検証済みDomain候補。
    private func candidate(byte: UInt8, name: String) throws -> ConnectionEndpointCandidate {
        try .init(endpointDigest: Data(repeating: byte, count: 32), displayName: name, transportKind: .bluetoothLE)
    }

    /// テスト用端末scopeを作ります。
    /// - Parameters:
    ///   - deviceID: ローカル端末ID。
    ///   - platform: Platform分類。
    /// - Returns: 同じUserに属する端末scope。
    private func makeScope(deviceID: UUID, platform: LocalDeviceScope.Platform = .iOS) -> LocalDeviceScope {
        .init(userScopeID: VehicleIdentityTestFixtures.scopeID, localDeviceScopeID: deviceID, platform: platform)
    }

    /// Migration済みStoreを開きます。
    /// - Parameter fixture: 一時DB。
    /// - Returns: 利用可能Store。
    /// - Throws: Storeが利用不能ならテスト失敗。
    private func requireStore(_ fixture: TemporaryVehicleDatabase) throws -> GRDBVehicleIdentityStore {
        guard case .available(let store) = GRDBVehicleIdentityStore.open(at: fixture.url, userScopeID: VehicleIdentityTestFixtures.scopeID, activeDigestKeyVersion: 1, createdAt: VehicleIdentityTestFixtures.recordedAt) else {
            throw VehiclePersistenceError.unavailable
        }
        return store
    }
}
