import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// v1 Migration、再open、未知Version、rollbackを検証します。
@Suite(.serialized)
struct VehicleIdentityMigrationTests {
    /// 空DBへv1を適用し、全テーブルとMigration IDを作成します。
    @Test
    func migratesEmptyDatabaseAndReopensIdempotently() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }

        let first = try requireStore(GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        ))
        let tables = try first.databasePool.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        #expect(tables.contains("vehicles"))
        #expect(tables.contains("vehicle_identifiers"))
        #expect(tables.contains("vehicle_identification_scans"))
        #expect(tables.contains("ecu_observations"))
        #expect(tables.contains("ecu_identification_values"))

        _ = try requireStore(GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        ))
    }

    /// 未知Migration IDがあるDBを自動変更せず利用不能にします。
    @Test
    func unknownMigrationVersionStopsNonDestructively() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try requireStore(GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        ))
        try store.databasePool.write { database in
            try database.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v999_unknown')")
        }

        guard case .unavailable(let unavailable) = GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1
        ) else {
            Issue.record("Unknown migration must not open")
            return
        }
        #expect(unavailable.reason == .unknownVersion)
        #expect(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    /// 初回scope INSERT失敗時にv1全体をrollbackします。
    @Test
    func migrationFailureRollsBackWholeSchema() throws {
        let queue = try DatabaseQueue()
        let migrator = VehicleIdentityDatabaseMigratorFactory.makeMigrator(
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 0,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        )
        #expect(throws: (any Error).self) {
            try migrator.migrate(queue)
        }
        let hasVehicles = try queue.read { try $0.tableExists("vehicles") }
        #expect(hasVehicles == false)
    }

    /// scope不一致を元DBを保ったまま停止します。
    @Test
    func scopeMismatchDoesNotReplaceDatabase() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        _ = try requireStore(GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1
        ))
        guard case .unavailable(let unavailable) = GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: UUID(),
            activeDigestKeyVersion: 1
        ) else {
            Issue.record("Mismatched scope must not open")
            return
        }
        #expect(unavailable.reason == .scopeMismatch)
        #expect(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    /// SQLiteでない既存ファイルを削除・空DB置換せずcorruptedとして停止します。
    @Test
    func corruptedFileStopsWithoutReplacement() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let original = Data("not-a-sqlite-database".utf8)
        try original.write(to: fixture.url)

        guard case .unavailable(let unavailable) = GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1
        ) else {
            Issue.record("Corrupted file must not open")
            return
        }
        #expect(unavailable.reason == .corrupted)
        #expect(try Data(contentsOf: fixture.url) == original)
    }

    /// Foreign Key異常を検出して既存DBを空DBへ置換せず停止します。
    @Test
    func foreignKeyCheckFailureStopsWithoutFallback() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        var store:GRDBVehicleIdentityStore?=try requireStore(GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1))
        store=nil
        var configuration=Configuration(); configuration.foreignKeysEnabled=false
        let queue=try DatabaseQueue(path:fixture.url.path,configuration:configuration)
        let scope=VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(), stamp=GRDBVehicleDateCodec.string(from:VehicleIdentityTestFixtures.recordedAt)
        try queue.write { database in
            try database.execute(sql:"INSERT INTO acquisition_streams(user_scope_id,stream_id,session_id,stream_kind,adapter_role,adapter_reference_id,connection_instance_id,stream_state,started_at_utc,ended_at_utc,next_record_sequence,next_chunk_sequence,record_revision,updated_at_utc) VALUES(?,?,?,'obd_pid','primary','broken-fk',?,'active',?,NULL,0,0,1,?)",arguments:[scope,UUID().uuidString.lowercased(),UUID().uuidString.lowercased(),UUID().uuidString.lowercased(),stamp,stamp])
        }
        guard case .unavailable(let unavailable)=GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1) else { Issue.record("FK-invalid DB must stop"); return }
        #expect(unavailable.reason == .corrupted)
        #expect(try queue.read { try Int.fetchOne($0,sql:"SELECT COUNT(*) FROM acquisition_streams") } == 1)
    }

    /// DB Check制約もvalid ScanのNULL vehicleを拒否します。
    @Test
    func schemaRejectsValidScanWithoutVehicle() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try requireStore(GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        ))
        let timestamp = GRDBVehicleDateCodec.string(from: VehicleIdentityTestFixtures.recordedAt)
        #expect(throws: DatabaseError.self) {
            try store.databasePool.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO vehicle_identification_scans (
                      user_scope_id, scan_id, vehicle_id, obd_connection_id, transport_kind,
                      diagnostic_protocol_kind, adapter_reference_id, decoder_version,
                      normalization_version, scan_status, decode_state, identity_validation_state,
                      termination_reason_code, started_at, finished_at, revision, created_at,
                      created_by_device_id, updated_at, updated_by_device_id
                    ) VALUES (?, ?, NULL, ?, 'ble', 'iso', 'adapter', 'decoder-v1',
                              'normalization-v1', 'completed', 'decoded', 'valid', NULL,
                              ?, ?, 1, ?, ?, ?, ?)
                    """,
                    arguments: [VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(), UUID().uuidString.lowercased(), UUID().uuidString.lowercased(), timestamp, timestamp, timestamp, VehicleIdentityTestFixtures.deviceID.uuidString.lowercased(), timestamp, VehicleIdentityTestFixtures.deviceID.uuidString.lowercased()]
                )
            }
        }
        let count = try store.databasePool.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM vehicle_identification_scans")
        }
        #expect(count == 0)
    }

    /// available結果からStoreを取り出します。
    /// - Parameter result: Store起動結果。
    /// - Returns: 利用可能Store。
    /// - Throws: unavailableならテストを失敗させます。
    private func requireStore(_ result: GRDBVehicleIdentityStoreOpenResult) throws -> GRDBVehicleIdentityStore {
        guard case .available(let store) = result else {
            throw VehiclePersistenceError.unavailable
        }
        return store
    }
}
