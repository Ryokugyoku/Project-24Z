import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// v3同期台帳と追記式v4強化Migration、Trigger、View境界を検証します。
@Suite(.serialized)
@MainActor
struct SyncPersistenceMigrationTests {
    /// 設計済み18テーブルと9つのactive-or-local Viewを追加します。
    @Test
    func migrationCreatesEighteenTablesAndNineViews() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        guard case .available(let store)=GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { Issue.record("v3 migration failed"); return }
        let expectedTables=["local_device_identity","paired_devices","device_trust_records","primary_mac_assignments","logical_sync_changes","sync_change_deliveries","received_changes","peer_sync_cursors","sync_batches","session_transfers","chunk_transfers","chunk_transfer_segments","vehicle_id_aliases","origin_entity_materializations","sync_conflicts","sync_conflict_candidates","sync_quarantine_items","wrapped_key_receipts"]
        let expectedViews=["active_or_local_vehicle_identification_scans","active_or_local_vehicle_identifiers","active_or_local_ecu_observations","active_or_local_ecu_identification_values","active_or_local_acquisition_sessions","active_or_local_acquisition_streams","active_or_local_clock_epochs","active_or_local_acquisition_gaps","active_or_local_log_chunks"]
        let objects=try store.databasePool.read { database in try Row.fetchAll(database,sql:"SELECT name,type FROM sqlite_master WHERE name IN ("+Array(repeating:"?",count:expectedTables.count+expectedViews.count).joined(separator:",")+")",arguments:StatementArguments(expectedTables+expectedViews)) }
        #expect(Set(objects.compactMap { $0["name"] as String? })==Set(expectedTables+expectedViews))
        #expect(objects.filter { ($0["type"] as String?)=="table" }.count==18)
        #expect(objects.filter { ($0["type"] as String?)=="view" }.count==9)
    }

    /// Membership未確立ではpaired状態をINSERTできません。
    @Test
    func membershipHardGateRejectsPairedPeer() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        guard case .available(let store)=GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { Issue.record("open failed"); return }
        let scope=VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(), peer=UUID().uuidString.lowercased(), stamp=GRDBVehicleDateCodec.string(from:VehicleIdentityTestFixtures.recordedAt)
        #expect(throws:(any Error).self) { try store.databasePool.write { database in
            try database.execute(sql:"INSERT INTO paired_devices(user_scope_id,peer_identity_id,device_role,device_identity_version,signing_key_version,signing_public_key,signing_key_fingerprint,key_agreement_key_version,key_agreement_public_key,key_agreement_key_fingerprint,tls_identity_key_version,tls_identity_public_key,tls_identity_key_fingerprint,tls_certificate_fingerprint,peer_pin_keychain_reference_id,membership_verification_state,membership_version,pairing_state,paired_at,unpaired_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'mac',1,1,?,?,1,?,?,1,?,?,?,?, 'verified',1,'paired',?,NULL,?,?,?,?,1)",arguments:[scope,peer,Data([1]),Data(repeating:1,count:32),Data([2]),Data(repeating:2,count:32),Data([3]),Data(repeating:3,count:32),Data(repeating:4,count:32),UUID().uuidString.lowercased(),stamp,stamp,peer,stamp,peer])
        }}
    }

    /// v3途中失敗でv1／v2行と外部Chunk fileを保持し、同期tableだけを部分作成しません。
    @Test
    func v3FailureRollsBackAndPreservesEarlierDataAndFile() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        let chunkURL=fixture.url.deletingLastPathComponent().appendingPathComponent("preserved-(UUID().uuidString).p24zc")
        defer { try? FileManager.default.removeItem(at:chunkURL) }
        let queue=try DatabaseQueue(path:fixture.url.path)
        let created=GRDBVehicleDateCodec.string(from:VehicleIdentityTestFixtures.recordedAt), scope=VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(), device=VehicleIdentityTestFixtures.deviceID.uuidString.lowercased(), vehicle=UUID().uuidString.lowercased(), session=UUID().uuidString.lowercased()
        var earlier=DatabaseMigrator()
        earlier.registerMigration(VehicleIdentitySchema.v1MigrationIdentifier) { database in
            try database.execute(sql:VehicleIdentitySchema.v1SQL)
            try database.execute(sql:"INSERT INTO database_scope(scope_row_id,user_scope_id,active_digest_key_version,created_at) VALUES(1,?,1,?)",arguments:[scope,created])
        }
        earlier.registerMigration(AcquisitionStorageSchema.v2MigrationIdentifier) { try $0.execute(sql:AcquisitionStorageSchema.v2SQL) }
        try earlier.migrate(queue)
        try queue.write { database in
            try database.execute(sql:"INSERT INTO vehicles(user_scope_id,vehicle_id,display_name_ciphertext,display_name_key_version,lifecycle_state,record_revision,display_name_revision,display_name_updated_at,display_name_updated_by_device_id,lifecycle_revision,lifecycle_updated_at,lifecycle_updated_by_device_id,archived_at,created_at,created_by_device_id,updated_at,updated_by_device_id) VALUES(?,?,NULL,NULL,'active',1,0,NULL,NULL,1,?,?,NULL,?,?,?,?)",arguments:[scope,vehicle,created,device,created,device,created,device])
            try database.execute(sql:"INSERT INTO acquisition_sessions(user_scope_id,session_id,vehicle_id,vehicle_binding_state,capture_state,disposition_state,integrity_state,end_reason_code,started_at_utc,ended_at_utc,reviewed_at_utc,disposition_requested_at_utc,disposition_completed_at_utc,created_by_device_id,record_revision,updated_at_utc,updated_by_device_id) VALUES(?,?,?,'registered_confirmed','ended_cleanly','saved','verified','user_stop',?,?,?, ?, ?,?,1,?,?)",arguments:[scope,session,vehicle,created,created,created,created,created,device,created,device])
            try database.execute(sql:"CREATE TABLE local_device_identity(dummy INTEGER) STRICT")
        }
        try Data([1,2,3,4]).write(to:chunkURL)
        let migrator=VehicleIdentityDatabaseMigratorFactory.makeMigrator(userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt)
        #expect(throws:(any Error).self) { try migrator.migrate(queue) }
        let state=try queue.read { database in
            (try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM vehicles WHERE vehicle_id=?",arguments:[vehicle]),try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM acquisition_sessions WHERE session_id=?",arguments:[session]),try database.tableExists("paired_devices"),try String.fetchAll(database,sql:"SELECT identifier FROM grdb_migrations ORDER BY rowid"))
        }
        #expect(state.0==1); #expect(state.1==1); #expect(!state.2)
        #expect(state.3==[VehicleIdentitySchema.v1MigrationIdentifier,AcquisitionStorageSchema.v2MigrationIdentifier])
        #expect(try Data(contentsOf:chunkURL)==Data([1,2,3,4]))
    }

    /// 旧v3の直接終端状態を削除せずv4へ移行し、未証明の遷移来歴をACKから隔離します。
    @Test
    func oldV3BusinessRowsUpgradeNonDestructivelyAndRemainBlockedAfterRestart() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        let chunkURL=fixture.url.deletingLastPathComponent().appendingPathComponent("legacy-v3-\(UUID().uuidString).p24zc")
        defer { try? FileManager.default.removeItem(at:chunkURL) }
        let queue=try DatabaseQueue(path:fixture.url.path)
        let ids=try installOldV3Fixture(in:queue)
        try Data([9,8,7,6]).write(to:chunkURL)
        let migrator=VehicleIdentityDatabaseMigratorFactory.makeMigrator(userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt)
        try migrator.migrate(queue)
        let migrated=try queue.read { database in
            (
                try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM session_transfers WHERE session_transfer_id=?",arguments:[ids.transfer]),
                try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM chunk_transfers WHERE chunk_transfer_id=?",arguments:[ids.chunkTransfer]),
                try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM wrapped_key_receipts WHERE key_envelope_id=?",arguments:[ids.keyEnvelope]),
                try Int.fetchOne(database,sql:"SELECT transition_step FROM session_transfers WHERE session_transfer_id=?",arguments:[ids.transfer]),
                try Int.fetchOne(database,sql:"SELECT transition_step FROM chunk_transfers WHERE chunk_transfer_id=?",arguments:[ids.chunkTransfer]),
                try Int.fetchOne(database,sql:"SELECT transition_step FROM wrapped_key_receipts WHERE key_envelope_id=?",arguments:[ids.keyEnvelope]),
                try Row.fetchAll(database,sql:"PRAGMA foreign_key_check")
            )
        }
        #expect(migrated.0==1); #expect(migrated.1==1); #expect(migrated.2==1)
        #expect(migrated.3==0); #expect(migrated.4==0); #expect(migrated.5==0); #expect(migrated.6.isEmpty)
        #expect(try Data(contentsOf:chunkURL)==Data([9,8,7,6]))
        guard case .available(let reopened)=GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { Issue.record("restart failed"); return }
        #expect(throws:SyncPersistenceError.blocked) { try reopened.localSyncRepository.markSessionTransferDurable(transferID:UUID(uuidString:ids.transfer)!,acknowledgementID:UUID(),durableAt:Date(),deviceID:UUID(uuidString:ids.peer)!) }
    }

    /// v4途中失敗ではALTERもMigration記録もrollbackし、旧v3行と外部fileを保持します。
    @Test
    func oldV3HardeningFailureRollsBackSchemaRowsAndExternalFile() throws {
        let fixture=try TemporaryVehicleDatabase(); defer { fixture.remove() }
        let chunkURL=fixture.url.deletingLastPathComponent().appendingPathComponent("legacy-v3-rollback-\(UUID().uuidString).p24zc")
        defer { try? FileManager.default.removeItem(at:chunkURL) }
        let queue=try DatabaseQueue(path:fixture.url.path)
        let ids=try installOldV3Fixture(in:queue)
        try queue.write { database in
            try database.execute(sql:"CREATE TRIGGER session_transfer_initial_state_guard BEFORE INSERT ON session_transfers BEGIN SELECT 1; END")
        }
        try Data([4,3,2,1]).write(to:chunkURL)
        let migrator=VehicleIdentityDatabaseMigratorFactory.makeMigrator(userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt)
        #expect(throws:(any Error).self) { try migrator.migrate(queue) }
        let rolledBack=try queue.read { database in
            (
                try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM session_transfers WHERE session_transfer_id=?",arguments:[ids.transfer]),
                try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM pragma_table_info('session_transfers') WHERE name='transition_step'"),
                try String.fetchAll(database,sql:"SELECT identifier FROM grdb_migrations ORDER BY rowid"),
                try Row.fetchAll(database,sql:"PRAGMA foreign_key_check")
            )
        }
        #expect(rolledBack.0==1); #expect(rolledBack.1==0)
        #expect(rolledBack.2==[VehicleIdentitySchema.v1MigrationIdentifier,AcquisitionStorageSchema.v2MigrationIdentifier,SyncPersistenceSchema.v3MigrationIdentifier])
        #expect(rolledBack.3.isEmpty); #expect(try Data(contentsOf:chunkURL)==Data([4,3,2,1]))
    }

    /// v1／v2／旧v3と直接終端状態の業務fixtureを作ります。
    private func installOldV3Fixture(in queue:DatabaseQueue) throws -> (transfer:String,chunkTransfer:String,keyEnvelope:String,peer:String) {
        let scope=VehicleIdentityTestFixtures.scopeID.uuidString.lowercased(), local=UUID().uuidString.lowercased(), peer=UUID().uuidString.lowercased(), batch=UUID().uuidString.lowercased(), transfer=UUID().uuidString.lowercased(), chunkTransfer=UUID().uuidString.lowercased(), session=UUID().uuidString.lowercased(), chunk=UUID().uuidString.lowercased(), keyEnvelope=UUID().uuidString.lowercased(), stamp=GRDBVehicleDateCodec.string(from:VehicleIdentityTestFixtures.recordedAt)
        var old=DatabaseMigrator()
        old.registerMigration(VehicleIdentitySchema.v1MigrationIdentifier) { database in
            try database.execute(sql:VehicleIdentitySchema.v1SQL)
            try database.execute(sql:"INSERT INTO database_scope(scope_row_id,user_scope_id,active_digest_key_version,created_at) VALUES(1,?,1,?)",arguments:[scope,stamp])
        }
        old.registerMigration(AcquisitionStorageSchema.v2MigrationIdentifier) { try $0.execute(sql:AcquisitionStorageSchema.v2SQL) }
        old.registerMigration(SyncPersistenceSchema.v3MigrationIdentifier) { try $0.execute(sql:SyncPersistenceSchema.v3SQL) }
        try old.migrate(queue)
        try queue.write { database in
            try database.execute(sql:"INSERT INTO local_device_identity(scope_row_id,user_scope_id,device_identity_id,device_role,device_identity_version,signing_key_version,signing_public_key,signing_key_fingerprint,signing_keychain_reference_id,key_agreement_key_version,key_agreement_public_key,key_agreement_key_fingerprint,key_agreement_keychain_reference_id,tls_identity_key_version,tls_identity_public_key,tls_identity_key_fingerprint,tls_certificate_fingerprint,tls_identity_keychain_reference_id,membership_state,membership_version,membership_credential_digest,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(1,?,?,'iphone',1,1,?,?,?,1,?,?,?,1,?,?,?,?, 'established',1,NULL,?,?,?,?,1)",arguments:[scope,local,Data([1]),Data(repeating:11,count:32),UUID().uuidString.lowercased(),Data([2]),Data(repeating:12,count:32),UUID().uuidString.lowercased(),Data([3]),Data(repeating:13,count:32),Data(repeating:14,count:32),UUID().uuidString.lowercased(),stamp,local,stamp,local])
            try database.execute(sql:"INSERT INTO paired_devices(user_scope_id,peer_identity_id,device_role,device_identity_version,signing_key_version,signing_public_key,signing_key_fingerprint,key_agreement_key_version,key_agreement_public_key,key_agreement_key_fingerprint,tls_identity_key_version,tls_identity_public_key,tls_identity_key_fingerprint,tls_certificate_fingerprint,peer_pin_keychain_reference_id,membership_verification_state,membership_version,pairing_state,paired_at,unpaired_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'mac',1,1,?,?,1,?,?,1,?,?,?,?, 'verified',1,'paired',?,NULL,?,?,?,?,1)",arguments:[scope,peer,Data([4]),Data(repeating:21,count:32),Data([5]),Data(repeating:22,count:32),Data([6]),Data(repeating:23,count:32),Data(repeating:24,count:32),UUID().uuidString.lowercased(),stamp,stamp,peer,stamp,peer])
            try database.execute(sql:"INSERT INTO device_trust_records(user_scope_id,peer_identity_id,trust_state,trust_generation,trusted_at,suspended_at,revoked_at,reason_code,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'trusted',1,?,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,peer,stamp,stamp,peer,stamp,peer])
            try database.execute(sql:"INSERT INTO sync_batches(user_scope_id,batch_id,transfer_id,peer_identity_id,direction,sync_protocol_version,capability_digest,batch_state,last_error_code,diagnostic_id,completed_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?, 'receive',1,?,'applying',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,batch,UUID().uuidString.lowercased(),peer,Data(repeating:31,count:32),stamp,peer,stamp,peer])
            try database.execute(sql:"INSERT INTO session_transfers(user_scope_id,session_transfer_id,batch_id,session_id,manifest_digest,expected_chunk_count,expected_ciphertext_bytes,transfer_state,durable_ack_id,durable_ack_binding_digest,durable_at,acknowledged_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,4,'verifying',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,transfer,batch,session,Data(repeating:1,count:32),stamp,peer,stamp,peer])
            try database.execute(sql:"INSERT INTO chunk_transfers(user_scope_id,chunk_transfer_id,session_transfer_id,session_id,chunk_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,ciphertext_digest,catalog_digest,record_format_version,compression_format_version,encryption_format_version,key_version,catalog_relative_path,catalog_storage_state,catalog_revision,catalog_created_at_utc,catalog_updated_at_utc,transfer_state,staging_relative_path,cataloged_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,0,?,0,0,0,0,1,4,4,4,?,?,1,1,1,1,'chunks/legacy','available',1,?,?,'cataloged',NULL,?,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer,transfer,session,chunk,UUID().uuidString.lowercased(),UUID().uuidString.lowercased(),Data(repeating:2,count:32),Data(repeating:3,count:32),stamp,stamp,stamp,stamp,peer,stamp,peer])
            try database.execute(sql:"INSERT INTO wrapped_key_receipts(user_scope_id,key_envelope_id,sender_identity_id,sender_signing_key_version,recipient_identity_id,recipient_agreement_key_version,trust_generation,key_purpose,wrapped_key_version,bound_session_id,bound_chunk_id,nonce_digest,envelope_digest,envelope_ciphertext,receipt_state,applied_keychain_reference_id,applied_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,1,?,1,1,'session_chunk',1,?,?,?,?,?,'applied',?,?,NULL,?,?,?,?,1)",arguments:[scope,keyEnvelope,peer,local,session,chunk,Data(repeating:4,count:32),Data(repeating:5,count:32),Data([1]),UUID().uuidString.lowercased(),stamp,stamp,peer,stamp,peer])
        }
        return(transfer,chunkTransfer,keyEnvelope,peer)
    }
}
