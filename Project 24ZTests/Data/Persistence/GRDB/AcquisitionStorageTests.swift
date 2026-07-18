import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// v2 Migration、Repository、再起動、車両bindingの耐久契約を検証します。
@Suite(.serialized)
@MainActor
struct AcquisitionStorageTests {
    /// v1既存行を保持したままv2を追記し、六つの目録tableを作ります。
    @Test
    func migrationPreservesV1AndAddsAcquisitionTables() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let tables = try store.databasePool.read { database in
            try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        }
        for name in ["acquisition_sessions","acquisition_streams","clock_epochs","acquisition_gaps","log_chunks","storage_integrity_findings"] {
            #expect(tables.contains(name))
        }
        #expect(tables.contains("vehicles"))
        let migrations = try store.databasePool.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") }
        #expect(migrations == VehicleIdentityDatabaseMigratorFactory.knownMigrationIdentifiers)
    }

    /// v2途中失敗はv2の部分tableを残さず、適用済みv1を保持します。
    @Test
    func v2MigrationFailureRollsBackWithoutReplacingV1() throws {
        let queue = try DatabaseQueue()
        var v1 = DatabaseMigrator()
        let createdAt = GRDBVehicleDateCodec.string(from: VehicleIdentityTestFixtures.recordedAt)
        v1.registerMigration(VehicleIdentitySchema.v1MigrationIdentifier) { database in
            try database.execute(sql: VehicleIdentitySchema.v1SQL)
            try database.execute(sql: "INSERT INTO database_scope(scope_row_id,user_scope_id,active_digest_key_version,created_at) VALUES(1,?,?,?)", arguments: [VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(),1,createdAt])
        }
        try v1.migrate(queue)
        try queue.write { try $0.execute(sql: "CREATE TABLE acquisition_sessions(dummy INTEGER) STRICT") }
        let migrator = VehicleIdentityDatabaseMigratorFactory.makeMigrator(userScopeID: VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion: 1,createdAt: VehicleIdentityTestFixtures.recordedAt)

        #expect(throws: (any Error).self) { try migrator.migrate(queue) }
        let state = try queue.read { database in
            (try database.tableExists("vehicles"), try database.tableExists("acquisition_streams"))
        }
        #expect(state.0)
        #expect(!state.1)
    }

    /// PIDとRaw CANを別Streamで開始し、進行中Sessionの重複をDBでも拒否します。
    @Test
    func startsSeparateStreamsAndRejectsConcurrentSession() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let values = makeSessionValues()
        try store.acquisitionRepository.start(session: values.session, streams: values.streams, epoch: values.epoch)
        let kinds = try store.databasePool.read { try String.fetchAll($0, sql: "SELECT stream_kind FROM acquisition_streams ORDER BY stream_kind") }
        #expect(kinds == ["obd_pid", "raw_can"])
        let other = makeSessionValues()
        #expect(throws: AcquisitionPersistenceError.conflict) {
            try store.acquisitionRepository.start(session: other.session, streams: other.streams, epoch: other.epoch)
        }
        let sessionCount = try store.databasePool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM acquisition_sessions") }
        #expect(sessionCount == 1)
    }

    /// 予約を再利用せず、file digestとcanonical目録digestを別値としてcommitします。
    @Test
    func reservesAndCommitsCatalogWithSeparatedDigests() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let values = makeSessionValues()
        try store.acquisitionRepository.start(session: values.session, streams: [values.streams[0]], epoch: values.epoch)
        let reservation = try store.acquisitionRepository.reserveChunk(streamID: values.streams[0].streamID, recordCount: 2, expectedStreamRevision: 1, updatedAt: values.session.startedAt.addingTimeInterval(1))
        let digester = SHA256AcquisitionChunkCatalogDigester()
        var entry = entryFor(reservation: reservation, epochID: values.epoch.clockEpochID, createdAt: values.session.startedAt.addingTimeInterval(2))
        entry = entryWithDigest(entry, try digester.digest(for: entry))
        let persisted = try store.acquisitionRepository.commitChunk(entry)
        #expect(persisted == entry)
        #expect(entry.ciphertextDigest != entry.catalogDigest)
        let stream = try store.databasePool.read { try Row.fetchOne($0, sql: "SELECT next_record_sequence,next_chunk_sequence FROM acquisition_streams") }
        #expect((stream?["next_record_sequence"] as Int64?) == 2)
        #expect((stream?["next_chunk_sequence"] as Int64?) == 1)
    }

    /// 再open後に未終端Sessionを未割当のままrecovery_requiredへ移します。
    @Test
    func restartRecoveryPreservesUnassignedSession() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        var store: GRDBVehicleIdentityStore? = try open(fixture)
        let values = makeSessionValues()
        try store!.acquisitionRepository.start(session: values.session, streams: values.streams, epoch: values.epoch)
        store = nil
        let reopened = try open(fixture)
        let recovered = try reopened.acquisitionRepository.recoverInterruptedSessions(at: values.session.startedAt.addingTimeInterval(10), deviceID: values.session.createdByDeviceID)
        #expect(recovered == [values.session.sessionID])
        let row = try reopened.databasePool.read { try Row.fetchOne($0, sql: "SELECT vehicle_id,vehicle_binding_state,capture_state FROM acquisition_sessions") }
        #expect((row?["vehicle_id"] as String?) == nil)
        #expect((row?["vehicle_binding_state"] as String?) == "unassigned_unidentified")
        #expect((row?["capture_state"] as String?) == "recovery_required")
    }

    /// binding競合でもactive Vehicleと未割当Sessionの両方を保持します。
    @Test
    func bindingFailurePreservesVehicleAndUnassignedSession() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let values = makeSessionValues()
        try store.acquisitionRepository.start(session: values.session, streams: [values.streams[0]], epoch: values.epoch)
        let vehicleID = UUID()
        let t = GRDBVehicleDateCodec.string(from: values.session.startedAt)
        try store.databasePool.write { database in
            try database.execute(sql: "INSERT INTO vehicles(user_scope_id,vehicle_id,display_name_ciphertext,display_name_key_version,lifecycle_state,record_revision,display_name_revision,display_name_updated_at,display_name_updated_by_device_id,lifecycle_revision,lifecycle_updated_at,lifecycle_updated_by_device_id,archived_at,created_at,created_by_device_id,updated_at,updated_by_device_id) VALUES(?,?,NULL,NULL,'active',1,0,NULL,NULL,1,?,?,NULL,?,?,?,?)", arguments: [VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(),vehicleID.uuidString.lowercased(),t,values.session.createdByDeviceID.uuidString.lowercased(),t,values.session.createdByDeviceID.uuidString.lowercased(),t,values.session.createdByDeviceID.uuidString.lowercased()])
        }
        #expect(throws: VehiclePersistenceError.conflict) {
            try store.acquisitionRepository.bind(sessionID: values.session.sessionID, vehicleID: vehicleID, expectedSessionRevision: 99, expectedVehicleLifecycleRevision: 1)
        }
        let counts = try store.databasePool.read { database in
            (try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicles"), try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM acquisition_sessions WHERE vehicle_id IS NULL"))
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
    }

    /// 孤立fileは再起動照合で削除せず隔離し、Findingを永続化します。
    @Test
    func restartReconciliationQuarantinesOrphanAndRecordsFinding() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let root = fixture.url.deletingLastPathComponent().appendingPathComponent("chunk-root")
        let values = makeSessionValues()
        let reservation = AcquisitionChunkReservation(chunkID: UUID(),sessionID: values.session.sessionID,streamID: values.streams[0].streamID,chunkSequence: 0,firstRecordSequence: 0,lastRecordSequence: 0)
        let bytes = Data([1,2,3])
        let chunk = PreparedAcquisitionChunk(reservation: reservation,clockEpochID: values.epoch.clockEpochID,firstMonotonicNanoseconds: 1,lastMonotonicNanoseconds: 1,plaintextSize: 3,compressedSize: 3,recordFormatVersion: 1,compressionFormatVersion: 1,encryptionFormatVersion: 1,keyVersion: 1,bytes: bytes)
        let failing = AtomicImmutableChunkFileStore(rootURL: root,capacityProvider: FakeChunkStorageCapacityProvider(capacity: 1_000_000),failureInjector: FakeChunkFilePersistenceFailureInjector(failingFaults: [.afterRename]),requiredSafetyMargin: 0)
        #expect(throws: AcquisitionPersistenceError.partialWrite) { try failing.finalize(chunk) }
        let restarted = AtomicImmutableChunkFileStore(rootURL: root,requiredSafetyMargin: 0)
        try RecoverAcquisitionStorageUseCase(fileStore: restarted,repository: store.acquisitionRepository).execute(recoveredAt: values.session.startedAt.addingTimeInterval(10),deviceID: values.session.createdByDeviceID)
        #expect(try restarted.finalizedRelativePaths().isEmpty)
        let finding = try store.databasePool.read { try Row.fetchOne($0, sql: "SELECT finding_kind,resolution_state,quarantine_relative_path FROM storage_integrity_findings") }
        #expect((finding?["finding_kind"] as String?) == "orphan_file")
        #expect((finding?["resolution_state"] as String?) == "quarantined")
        #expect((finding?["quarantine_relative_path"] as String?)?.hasPrefix("quarantine/") == true)
    }

    /// fileのないavailable目録は読み飛ばさずmissingとFindingへ移します。
    @Test
    func restartReconciliationMarksMissingCatalogFile() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let values = makeSessionValues()
        try store.acquisitionRepository.start(session: values.session,streams: [values.streams[0]],epoch: values.epoch)
        let reservation = try store.acquisitionRepository.reserveChunk(streamID: values.streams[0].streamID,recordCount: 1,expectedStreamRevision: 1,updatedAt: values.session.startedAt.addingTimeInterval(1))
        var entry = entryFor(reservation: reservation,epochID: values.epoch.clockEpochID,createdAt: values.session.startedAt.addingTimeInterval(2))
        entry = entryWithDigest(entry,try SHA256AcquisitionChunkCatalogDigester().digest(for: entry))
        _ = try store.acquisitionRepository.commitChunk(entry)
        let root = fixture.url.deletingLastPathComponent().appendingPathComponent("missing-root")
        let fileStore = AtomicImmutableChunkFileStore(rootURL: root,requiredSafetyMargin: 0)
        try RecoverAcquisitionStorageUseCase(fileStore: fileStore,repository: store.acquisitionRepository).execute(recoveredAt: values.session.startedAt.addingTimeInterval(10),deviceID: values.session.createdByDeviceID)
        let state = try store.databasePool.read { database in
            (try String.fetchOne(database,sql: "SELECT storage_state FROM log_chunks"),try String.fetchOne(database,sql: "SELECT finding_kind FROM storage_integrity_findings"))
        }
        #expect(state.0 == "missing")
        #expect(state.1 == "missing_file")
    }

    /// 未割当Sessionもデータを保持したまま正常終了でき、新Sessionを開始できます。
    @Test
    func unassignedSessionCanEndAndDoesNotBlockNextSession() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try open(fixture)
        let first = makeSessionValues()
        try store.acquisitionRepository.start(session: first.session,streams: first.streams,epoch: first.epoch)
        try store.acquisitionRepository.finishSession(sessionID: first.session.sessionID,expectedSessionRevision: 1,reason: .userStop,endedAt: first.session.startedAt.addingTimeInterval(5),deviceID: first.session.createdByDeviceID)
        let second = makeSessionValues()
        try store.acquisitionRepository.start(session: second.session,streams: [second.streams[0]],epoch: second.epoch)
        let firstRow = try store.databasePool.read { try Row.fetchOne($0, sql: "SELECT vehicle_id,capture_state FROM acquisition_sessions WHERE session_id=?", arguments: [first.session.sessionID.uuidString.lowercased()]) }
        #expect((firstRow?["vehicle_id"] as String?) == nil)
        #expect((firstRow?["capture_state"] as String?) == "ended_cleanly")
    }

    /// Migration済みStoreを取り出します。
    private func open(_ fixture: TemporaryVehicleDatabase) throws -> GRDBVehicleIdentityStore {
        guard case .available(let store) = GRDBVehicleIdentityStore.open(at: fixture.url,userScopeID: VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion: 1,createdAt: VehicleIdentityTestFixtures.recordedAt) else { throw VehiclePersistenceError.unavailable }
        return store
    }

    /// 未割当Session、PID／Raw CAN、Epochを作ります。
    private func makeSessionValues() -> (session: AcquisitionSession, streams: [AcquisitionStream], epoch: AcquisitionClockEpoch) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID(), deviceID = UUID()
        let session = AcquisitionSession(sessionID: sessionID,vehicleID: nil,vehicleBindingState: .unassignedUnidentified,captureState: .recording,dispositionState: .pendingDecision,integrityState: .unchecked,endReason: nil,startedAt: now,endedAt: nil,createdByDeviceID: deviceID,revision: 1,updatedAt: now,updatedByDeviceID: deviceID)
        let pid = AcquisitionStream(streamID: UUID(),sessionID: sessionID,kind: .obdPID,adapterRole: .primary,adapterReferenceID: "primary-\(UUID())",connectionInstanceID: UUID(),state: .active,startedAt: now,endedAt: nil,nextRecordSequence: 0,nextChunkSequence: 0,revision: 1,updatedAt: now)
        let can = AcquisitionStream(streamID: UUID(),sessionID: sessionID,kind: .rawCAN,adapterRole: .secondary,adapterReferenceID: "secondary-\(UUID())",connectionInstanceID: UUID(),state: .active,startedAt: now,endedAt: nil,nextRecordSequence: 0,nextChunkSequence: 0,revision: 1,updatedAt: now)
        return (session,[pid,can],AcquisitionClockEpoch(clockEpochID: UUID(),sessionID: sessionID,processInstanceID: UUID(),deviceID: deviceID,wallClockAnchor: now,anchorUncertaintyNanoseconds: 1,startedAt: now))
    }

    /// Digest前の目録値を作ります。
    private func entryFor(reservation: AcquisitionChunkReservation, epochID: UUID, createdAt: Date) -> AcquisitionChunkCatalogEntry {
        AcquisitionChunkCatalogEntry(reservation: reservation,clockEpochID: epochID,firstMonotonicNanoseconds: 10,lastMonotonicNanoseconds: 20,plaintextSize: 3,compressedSize: 3,ciphertextSize: 3,recordFormatVersion: 1,compressionFormatVersion: 1,encryptionFormatVersion: 1,keyVersion: 1,ciphertextDigest: Data(repeating: 7,count: 32),catalogDigest: Data(repeating: 0,count: 32),relativePath: "chunks/\(reservation.sessionID.uuidString.lowercased())/\(reservation.streamID.uuidString.lowercased())/00000000000000000000-\(reservation.chunkID.uuidString.lowercased()).p24zc",createdAt: createdAt)
    }

    /// 計算済みcatalog digestへ差し替えます。
    private func entryWithDigest(_ e: AcquisitionChunkCatalogEntry, _ digest: Data) -> AcquisitionChunkCatalogEntry {
        AcquisitionChunkCatalogEntry(reservation:e.reservation,clockEpochID:e.clockEpochID,firstMonotonicNanoseconds:e.firstMonotonicNanoseconds,lastMonotonicNanoseconds:e.lastMonotonicNanoseconds,plaintextSize:e.plaintextSize,compressedSize:e.compressedSize,ciphertextSize:e.ciphertextSize,recordFormatVersion:e.recordFormatVersion,compressionFormatVersion:e.compressionFormatVersion,encryptionFormatVersion:e.encryptionFormatVersion,keyVersion:e.keyVersion,ciphertextDigest:e.ciphertextDigest,catalogDigest:digest,relativePath:e.relativePath,createdAt:e.createdAt)
    }
}
