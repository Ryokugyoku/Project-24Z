import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// Fake peer／Fake codec入力でローカル同期状態機械を検証します。
@Suite(.serialized)
@MainActor
struct SyncPersistenceStateMachineTests {
    /// Origin／Streamごとに0から連続採番し、前ChangeとChainを維持します。
    @Test
    func originSequenceStartsAtZeroAndChainsWithoutOverwrite() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        _=try provisionFakePeer(context.store)
        let origin=UUID(), first=makeDraft(origin:origin), second=makeDraft(origin:origin)
        let persisted0=try context.store.localSyncRepository.appendLogicalChange(first)
        let persisted1=try context.store.localSyncRepository.appendLogicalChange(second)
        #expect(persisted0.sequence==0); #expect(persisted0.previousChangeID==nil)
        #expect(persisted1.sequence==1); #expect(persisted1.previousChangeID==first.originChangeID); #expect(persisted1.previousChainDigest==persisted0.chainDigest)
        #expect(throws:SyncPersistenceError.conflict) { try context.store.localSyncRepository.appendLogicalChange(second) }
        #expect(throws:(any Error).self) { try context.store.databasePool.write { database in
            try database.execute(sql:"UPDATE logical_sync_changes SET chain_digest=? WHERE logical_change_id=?",arguments:[Data(repeating:9,count:32),first.logicalChangeID.uuidString.lowercased()])
        }}
    }

    /// validated ReceiptではCursorを止め、受信元への反射を拒否します。
    @Test
    func cursorStopsBeforeAppliedAndRelayDoesNotReflect() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        let peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let draft=makeDraft(origin:UUID()), persisted=try context.store.localSyncRepository.appendLogicalChange(draft)
        let receipt=UUID(), stamp=timestamp()
        try context.store.databasePool.write { database in
            try database.execute(sql:"INSERT INTO received_changes(user_scope_id,receipt_id,source_peer_identity_id,batch_id,logical_change_id,origin_device_identity_id,origin_change_id,stream_kind,change_sequence,previous_chain_digest,chain_digest,entity_kind,entity_id,entity_schema_version,content_digest,relay_hop_count,apply_state,applied_revision,conflict_id,quarantine_id,applied_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'validated',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,receipt.uuidString.lowercased(),peer.uuidString.lowercased(),batch.uuidString.lowercased(),draft.logicalChangeID.uuidString.lowercased(),draft.originDeviceIdentityID.uuidString.lowercased(),draft.originChangeID.uuidString.lowercased(),draft.streamKind.rawValue,persisted.sequence,persisted.previousChainDigest,persisted.chainDigest,draft.entityKind,draft.entityID.uuidString.lowercased(),draft.entitySchemaVersion,draft.contentDigest,1,stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
            try database.execute(sql:"INSERT INTO peer_sync_cursors(user_scope_id,peer_identity_id,direction,origin_device_identity_id,stream_kind,next_expected_sequence,last_change_id,last_chain_digest,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'received',?,?,0,NULL,NULL,?,?,?,?,1)",arguments:[scope,peer.uuidString.lowercased(),draft.originDeviceIdentityID.uuidString.lowercased(),draft.streamKind.rawValue,stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
        }
        #expect(throws:SyncPersistenceError.blocked) { try context.store.localSyncRepository.advanceCursor(peerIdentityID:peer,direction:"received",originDeviceIdentityID:draft.originDeviceIdentityID,streamKind:draft.streamKind,updatedAt:Date(),deviceID:peer) }
        #expect(throws:(any Error).self) { try context.store.databasePool.write { database in
            try database.execute(sql:"INSERT INTO sync_change_deliveries(user_scope_id,delivery_id,logical_change_id,target_peer_identity_id,relay_device_identity_id,relayed_from_peer_identity_id,relay_hop_count,delivery_state,batch_id,ack_id,acked_sequence,acked_chain_digest,retry_count,next_retry_at,suppression_reason,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,1,'pending',NULL,NULL,NULL,NULL,0,NULL,NULL,?,?,?,?,1)",arguments:[scope,UUID().uuidString.lowercased(),draft.logicalChangeID.uuidString.lowercased(),peer.uuidString.lowercased(),UUID().uuidString.lowercased(),peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
        }}
    }

    /// Segment穴を拒否し、file durable／cataloged完了後だけDurable ACKを確定します。
    @Test
    func durableAckRequiresContiguousVerifiedSegmentsAndCatalog() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        let peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let transfer=UUID(), chunkTransfer=UUID(), session=UUID(), stream=UUID(), chunk=UUID(), epoch=UUID(), acknowledgement=UUID(), stamp=timestamp(), device=peer.uuidString.lowercased()
        let ciphertextDigest=Data(repeating:6,count:32), catalogDigest=Data(repeating:9,count:32)
        try context.store.databasePool.write { database in
            let local:String=try String.fetchOne(database,sql:"SELECT device_identity_id FROM local_device_identity")!
            try database.execute(sql:"INSERT INTO acquisition_sessions(user_scope_id,session_id,vehicle_id,vehicle_binding_state,capture_state,disposition_state,integrity_state,end_reason_code,started_at_utc,ended_at_utc,reviewed_at_utc,disposition_requested_at_utc,disposition_completed_at_utc,created_by_device_id,record_revision,updated_at_utc,updated_by_device_id) VALUES(?,?,NULL,'unassigned_unidentified','ended_cleanly','pending_decision','verified','user_stop',?,?,NULL,NULL,NULL,?,1,?,?)",arguments:[scope,session.uuidString.lowercased(),stamp,stamp,device,stamp,device])
            try database.execute(sql:"INSERT INTO acquisition_streams(user_scope_id,stream_id,session_id,stream_kind,adapter_role,adapter_reference_id,connection_instance_id,stream_state,started_at_utc,ended_at_utc,next_record_sequence,next_chunk_sequence,record_revision,updated_at_utc) VALUES(?,?,?,'obd_pid','primary','fake',?,'stopped',?,?,1,1,1,?)",arguments:[scope,stream.uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),stamp,stamp,stamp])
            try database.execute(sql:"INSERT INTO clock_epochs(user_scope_id,clock_epoch_id,session_id,process_instance_id,device_id,monotonic_clock_kind,wall_clock_anchor_utc,anchor_uncertainty_ns,started_at_utc,ended_at_utc,revision) VALUES(?,?,?,?,?,'continuous_host_time',?,0,?,?,1)",arguments:[scope,epoch.uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),device,stamp,stamp,stamp])
            try database.execute(sql:"INSERT INTO log_chunks(user_scope_id,chunk_id,session_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,record_format_version,compression_format_version,encryption_format_version,key_version,ciphertext_digest,catalog_digest,relative_path,storage_state,revision,created_at_utc,updated_at_utc) VALUES(?,?,?,?,0,?,0,0,0,0,1,4,4,4,1,1,1,1,?,?,'chunks/test','available',1,?,?)",arguments:[scope,chunk.uuidString.lowercased(),session.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),ciphertextDigest,catalogDigest,stamp,stamp])
            let manifest=try MaterializedEntityDigestV1.sessionManifestDigest(database:database,scope:scope,sessionID:session.uuidString.lowercased())
            try database.execute(sql:"INSERT INTO session_transfers(user_scope_id,session_transfer_id,batch_id,session_id,manifest_digest,expected_chunk_count,expected_ciphertext_bytes,transfer_state,durable_ack_id,durable_ack_binding_digest,durable_at,acknowledged_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,4,'manifest_pending',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,transfer.uuidString.lowercased(),batch.uuidString.lowercased(),session.uuidString.lowercased(),manifest,stamp,device,stamp,device])
            try advanceSessionToVerifying(database, transferID:transfer, stamp:stamp, device:peer)
            try database.execute(sql:"INSERT INTO chunk_transfers(user_scope_id,chunk_transfer_id,session_transfer_id,session_id,chunk_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,ciphertext_digest,catalog_digest,record_format_version,compression_format_version,encryption_format_version,key_version,catalog_relative_path,catalog_storage_state,catalog_revision,catalog_created_at_utc,catalog_updated_at_utc,transfer_state,staging_relative_path,cataloged_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,0,?,0,0,0,0,1,4,4,4,?,?,1,1,1,1,'chunks/test','available',1,?,?,'pending',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),transfer.uuidString.lowercased(),session.uuidString.lowercased(),chunk.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),ciphertextDigest,catalogDigest,stamp,stamp,stamp,device,stamp,device])
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='receiving',transition_step=transition_step+1,staging_relative_path='staging/chunk',revision=revision+1 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()])
            try database.execute(sql:"INSERT INTO chunk_transfer_segments(user_scope_id,chunk_transfer_id,segment_index,byte_offset,byte_length,segment_digest,segment_state,received_at,verified_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,0,0,2,?,'expected',NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),Data(repeating:7,count:32),stamp,device,stamp,device])
            try receiveAndVerifySegment(database, chunkTransferID:chunkTransfer, index:0, stamp:stamp)
            let keyEnvelope=UUID()
            try database.execute(sql:"INSERT INTO wrapped_key_receipts(user_scope_id,key_envelope_id,sender_identity_id,sender_signing_key_version,recipient_identity_id,recipient_agreement_key_version,trust_generation,key_purpose,wrapped_key_version,bound_session_id,bound_chunk_id,nonce_digest,envelope_digest,envelope_ciphertext,receipt_state,applied_keychain_reference_id,applied_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,1,?,1,1,'session_chunk',1,?,?,?, ?,?,'received',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,keyEnvelope.uuidString.lowercased(),device,local,session.uuidString.lowercased(),chunk.uuidString.lowercased(),Data(repeating:41,count:32),Data(repeating:42,count:32),Data([1]),stamp,device,stamp,device])
            try verifyAndApplyWrappedKey(database, keyEnvelopeID:keyEnvelope, stamp:stamp)
        }
        #expect(throws:SyncPersistenceError.blocked) { try context.store.localSyncRepository.markSessionTransferDurable(transferID:transfer,acknowledgementID:UUID(),durableAt:Date(),deviceID:peer) }
        #expect(throws:(any Error).self) { try context.store.databasePool.write { try $0.execute(sql:"UPDATE chunk_transfers SET transfer_state='segments_complete',transition_step=transition_step+1,revision=2 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()]) } }
        try context.store.databasePool.write { database in
            try database.execute(sql:"INSERT INTO chunk_transfer_segments(user_scope_id,chunk_transfer_id,segment_index,byte_offset,byte_length,segment_digest,segment_state,received_at,verified_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,1,2,2,?,'expected',NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),Data(repeating:8,count:32),stamp,device,stamp,device])
            try receiveAndVerifySegment(database, chunkTransferID:chunkTransfer, index:1, stamp:stamp)
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='segments_complete',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()])
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='verified',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()])
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='file_durable',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()])
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='cataloged',transition_step=transition_step+1,staging_relative_path=NULL,cataloged_at=?,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[stamp,chunkTransfer.uuidString.lowercased()])
        }
        try context.store.localSyncRepository.markSessionTransferDurable(transferID:transfer,acknowledgementID:acknowledgement,durableAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.markSessionTransferDurable(transferID:transfer,acknowledgementID:acknowledgement,durableAt:Date(),deviceID:peer)
        #expect(throws:SyncPersistenceError.conflict) { try context.store.localSyncRepository.markSessionTransferDurable(transferID:transfer,acknowledgementID:UUID(),durableAt:Date(),deviceID:peer) }
        let state=try context.store.databasePool.read { try String.fetchOne($0,sql:"SELECT transfer_state FROM session_transfers") }
        #expect(state=="durable")
        guard case .available(let reopened)=GRDBVehicleIdentityStore.open(at:context.fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { Issue.record("reopen failed"); return }
        try reopened.localSyncRepository.markSessionTransferDurable(transferID:transfer,acknowledgementID:acknowledgement,durableAt:Date(),deviceID:peer)
    }

    /// 別Session／Stream／Sequence、Catalog、階層Entity欠落、別Session用KeyをDurable ACKで拒否します。
    @Test
    func durableAckRejectsCrossSessionStreamSequenceCatalogMissingHierarchyAndMisboundKey() throws {
        for mismatch in DurableMismatch.allCases {
            let prepared=try makeCatalogedTransfer(mismatch:mismatch)
            defer { prepared.context.fixture.remove() }
            #expect(throws:SyncPersistenceError.blocked) {
                try prepared.context.store.localSyncRepository.markSessionTransferDurable(
                    transferID:prepared.transfer,
                    acknowledgementID:UUID(),
                    durableAt:Date(),
                    deviceID:prepared.peer
                )
            }
        }
    }

    /// verifying／cataloged／verified／appliedの直接INSERTではDurable ACK用状態を作れません。
    @Test
    func durableAckStatesRejectDirectInsertBypass() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        let peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let transfer=UUID(), chunkTransfer=UUID(), session=UUID(), stream=UUID(), chunk=UUID(), epoch=UUID(), stamp=timestamp(), actor=peer.uuidString.lowercased()
        try context.store.databasePool.write { database in
            let local:String=try String.fetchOne(database,sql:"SELECT device_identity_id FROM local_device_identity")!
            #expect(throws:(any Error).self) {
                try database.execute(sql:"INSERT INTO session_transfers(user_scope_id,session_transfer_id,batch_id,session_id,manifest_digest,expected_chunk_count,expected_ciphertext_bytes,transfer_state,durable_ack_id,durable_ack_binding_digest,durable_at,acknowledged_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,4,'verifying',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,transfer.uuidString.lowercased(),batch.uuidString.lowercased(),session.uuidString.lowercased(),Data(repeating:1,count:32),stamp,actor,stamp,actor])
            }
            try database.execute(sql:"INSERT INTO session_transfers(user_scope_id,session_transfer_id,batch_id,session_id,manifest_digest,expected_chunk_count,expected_ciphertext_bytes,transfer_state,durable_ack_id,durable_ack_binding_digest,durable_at,acknowledged_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,4,'manifest_pending',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,transfer.uuidString.lowercased(),batch.uuidString.lowercased(),session.uuidString.lowercased(),Data(repeating:1,count:32),stamp,actor,stamp,actor])
            #expect(throws:(any Error).self) {
                try database.execute(sql:"UPDATE session_transfers SET transition_step=2 WHERE session_transfer_id=?",arguments:[transfer.uuidString.lowercased()])
            }
            #expect(throws:(any Error).self) {
                try database.execute(sql:"INSERT INTO chunk_transfers(user_scope_id,chunk_transfer_id,session_transfer_id,session_id,chunk_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,ciphertext_digest,catalog_digest,record_format_version,compression_format_version,encryption_format_version,key_version,catalog_relative_path,catalog_storage_state,catalog_revision,catalog_created_at_utc,catalog_updated_at_utc,transfer_state,staging_relative_path,cataloged_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,0,?,0,0,0,0,1,4,4,4,?,?,1,1,1,1,'chunks/test','available',1,?,?,'cataloged',NULL,?,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),transfer.uuidString.lowercased(),session.uuidString.lowercased(),chunk.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),Data(repeating:2,count:32),Data(repeating:3,count:32),stamp,stamp,stamp,stamp,actor,stamp,actor])
            }
            try database.execute(sql:"INSERT INTO chunk_transfers(user_scope_id,chunk_transfer_id,session_transfer_id,session_id,chunk_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,ciphertext_digest,catalog_digest,record_format_version,compression_format_version,encryption_format_version,key_version,catalog_relative_path,catalog_storage_state,catalog_revision,catalog_created_at_utc,catalog_updated_at_utc,transfer_state,staging_relative_path,cataloged_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,0,?,0,0,0,0,1,4,4,4,?,?,1,1,1,1,'chunks/test','available',1,?,?,'pending',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),transfer.uuidString.lowercased(),session.uuidString.lowercased(),chunk.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),Data(repeating:2,count:32),Data(repeating:3,count:32),stamp,stamp,stamp,actor,stamp,actor])
            #expect(throws:(any Error).self) {
                try database.execute(sql:"INSERT INTO chunk_transfer_segments(user_scope_id,chunk_transfer_id,segment_index,byte_offset,byte_length,segment_digest,segment_state,received_at,verified_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,0,0,4,?,'verified',?,?,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),Data(repeating:4,count:32),stamp,stamp,stamp,actor,stamp,actor])
            }
            #expect(throws:(any Error).self) {
                try database.execute(sql:"INSERT INTO wrapped_key_receipts(user_scope_id,key_envelope_id,sender_identity_id,sender_signing_key_version,recipient_identity_id,recipient_agreement_key_version,trust_generation,key_purpose,wrapped_key_version,bound_session_id,bound_chunk_id,nonce_digest,envelope_digest,envelope_ciphertext,receipt_state,applied_keychain_reference_id,applied_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,1,?,1,1,'session_chunk',1,?,?,?,?,?,'applied',?,?,NULL,?,?,?,?,1)",arguments:[scope,UUID().uuidString.lowercased(),actor,local,session.uuidString.lowercased(),chunk.uuidString.lowercased(),Data(repeating:5,count:32),Data(repeating:6,count:32),Data([1]),UUID().uuidString.lowercased(),stamp,stamp,actor,stamp,actor])
            }
        }
    }

    /// 再起動後の保存済みACK binding改変を、同じACK IDでも拒否します。
    @Test
    func durableAckRejectsMutatedBindingAfterRestart() throws {
        let prepared=try makeCatalogedTransfer(mismatch:nil)
        defer { prepared.context.fixture.remove() }
        let acknowledgement=UUID()
        try prepared.context.store.localSyncRepository.markSessionTransferDurable(transferID:prepared.transfer,acknowledgementID:acknowledgement,durableAt:Date(),deviceID:prepared.peer)
        try prepared.context.store.databasePool.write { database in
            try database.execute(sql:"UPDATE session_transfers SET durable_ack_binding_digest=? WHERE user_scope_id=? AND session_transfer_id=?",arguments:[Data(repeating:99,count:32),scope,prepared.transfer.uuidString.lowercased()])
        }
        guard case .available(let reopened)=GRDBVehicleIdentityStore.open(at:prepared.context.fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { Issue.record("reopen failed"); return }
        #expect(throws:SyncPersistenceError.blocked) { try reopened.localSyncRepository.markSessionTransferDurable(transferID:prepared.transfer,acknowledgementID:acknowledgement,durableAt:Date(),deviceID:prepared.peer) }
    }

    /// inserted Projection、Receipt、公開切替が途中失敗時に同じtransactionでrollbackします。
    @Test
    func materializationAndAliasPublicationAreAtomic() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        let peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let origin=UUID(), originVehicle=UUID(), vehicle=UUID(), alias1=UUID(), scan1=UUID(), materialization1=UUID(), receipt1=UUID(), stamp=timestamp()
        let first=makeDraft(origin:origin,entityKind:"vehicle_identification_scan",entityID:scan1,originVehicleID:originVehicle)
        let persisted=try context.store.localSyncRepository.appendLogicalChange(first)
        try context.store.databasePool.write { try insertVehicle($0,id:vehicle,device:peer,stamp:stamp) }
        let expectedDigest=try plannedScanDigest(context.store,scan:scan1,vehicle:vehicle,device:peer,stamp:stamp)
        try context.store.databasePool.write { database in
            try insertAlias(database,id:alias1,peer:peer,originVehicle:originVehicle,vehicle:vehicle,generation:1,previous:nil,expectedCount:1,stamp:stamp)
            try insertScanMaterialization(database,id:materialization1,change:first,alias:alias1,generation:1,vehicle:vehicle,scan:scan1,expectedDigest:expectedDigest,stamp:stamp,device:peer)
            try insertReceipt(database,id:receipt1,batch:batch,peer:peer,draft:first,persisted:persisted,stamp:stamp)
            try database.execute(sql:"INSERT INTO peer_sync_cursors(user_scope_id,peer_identity_id,direction,origin_device_identity_id,stream_kind,next_expected_sequence,last_change_id,last_chain_digest,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'received',?,?,0,NULL,NULL,?,?,?,?,1)",arguments:[scope,peer.uuidString.lowercased(),origin.uuidString.lowercased(),first.streamKind.rawValue,stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
        }
        try context.store.localSyncRepository.sealAliasGraphManifest(aliasID:alias1,updatedAt:Date(),deviceID:peer)
        #expect(throws:SyncPersistenceError.blocked) { try context.store.localSyncRepository.markAliasReady(aliasID:alias1,readyAt:Date(),deviceID:peer) }
        #expect(throws:SyncPersistenceError.unavailable) {
            try context.store.localSyncRepository.applyInsertedProjection(materializationID:materialization1,receiptID:receipt1,appliedAt:Date(),deviceID:peer,crashInjection:.afterBusinessInsert) {
                try self.insertScan($0,id:scan1,vehicle:vehicle,device:peer,stamp:stamp)
            }
        }
        let rolledBack=try context.store.databasePool.read { database in
            (try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM vehicle_identification_scans WHERE scan_id=?",arguments:[scan1.uuidString.lowercased()]),try String.fetchOne(database,sql:"SELECT materialization_state FROM origin_entity_materializations WHERE materialization_id=?",arguments:[materialization1.uuidString.lowercased()]),try String.fetchOne(database,sql:"SELECT apply_state FROM received_changes WHERE receipt_id=?",arguments:[receipt1.uuidString.lowercased()]))
        }
        #expect(rolledBack.0==0); #expect(rolledBack.1=="projected"); #expect(rolledBack.2=="validated")
        try context.store.localSyncRepository.applyInsertedProjection(materializationID:materialization1,receiptID:receipt1,appliedAt:Date(),deviceID:peer) {
            try self.insertScan($0,id:scan1,vehicle:vehicle,device:peer,stamp:stamp)
        }
        try context.store.localSyncRepository.advanceCursor(peerIdentityID:peer,direction:"received",originDeviceIdentityID:origin,streamKind:first.streamKind,updatedAt:Date(),deviceID:peer)
        let nextSequence=try context.store.databasePool.read { try Int.fetchOne($0,sql:"SELECT next_expected_sequence FROM peer_sync_cursors WHERE peer_identity_id=?",arguments:[peer.uuidString.lowercased()]) }
        #expect(nextSequence==1)
        try context.store.localSyncRepository.markAliasReady(aliasID:alias1,readyAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.publishAlias(aliasID:alias1,activatedAt:Date(),deviceID:peer)
        #expect(try visibleScanIDs(context.store)==[scan1.uuidString.lowercased()])

        let alias2=UUID(), scan2=UUID(), materialization2=UUID(), receipt2=UUID()
        let second=makeDraft(origin:origin,entityKind:"vehicle_identification_scan",entityID:scan2,originVehicleID:originVehicle)
        let persisted2=try context.store.localSyncRepository.appendLogicalChange(second)
        let expectedDigest2=try plannedScanDigest(context.store,scan:scan2,vehicle:vehicle,device:peer,stamp:stamp)
        try context.store.databasePool.write { database in
            try insertAlias(database,id:alias2,peer:peer,originVehicle:originVehicle,vehicle:vehicle,generation:2,previous:alias1,expectedCount:1,stamp:stamp)
            try insertScanMaterialization(database,id:materialization2,change:second,alias:alias2,generation:2,vehicle:vehicle,scan:scan2,expectedDigest:expectedDigest2,stamp:stamp,device:peer)
            try insertReceipt(database,id:receipt2,batch:batch,peer:peer,draft:second,persisted:persisted2,stamp:stamp)
        }
        try context.store.localSyncRepository.sealAliasGraphManifest(aliasID:alias2,updatedAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.applyInsertedProjection(materializationID:materialization2,receiptID:receipt2,appliedAt:Date(),deviceID:peer) { try self.insertScan($0,id:scan2,vehicle:vehicle,device:peer,stamp:stamp) }
        try context.store.localSyncRepository.markAliasReady(aliasID:alias2,readyAt:Date(),deviceID:peer)
        #expect(throws:SyncPersistenceError.unavailable) { try context.store.localSyncRepository.publishAlias(aliasID:alias2,activatedAt:Date(),deviceID:peer,crashInjection:.afterOldAliasSuperseded) }
        #expect(try visibleScanIDs(context.store)==[scan1.uuidString.lowercased()])
        try context.store.localSyncRepository.publishAlias(aliasID:alias2,activatedAt:Date(),deviceID:peer)
        #expect(try visibleScanIDs(context.store)==[scan2.uuidString.lowercased()])
    }

    /// Identifierのinserted候補が既存行へのlinked duplicateへ切り替わっても途中状態を残しません。
    @Test
    func identifierInsertedCandidateConvergesToLinkedDuplicateAtomically() throws {
        let context=try makeContext(); defer { context.fixture.remove() }
        let peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let origin=UUID(), vehicle=UUID(), scan=UUID(), identifier=UUID(), originVehicle=UUID(), remoteScan=UUID(), remoteIdentifier=UUID(), alias=UUID(), scanMaterialization=UUID(), materialization=UUID(), scanReceipt=UUID(), receipt=UUID(), stamp=timestamp()
        let lookupDigest=Data(repeating:71,count:32)
        try context.store.databasePool.write { database in
            try insertVehicle(database,id:vehicle,device:peer,stamp:stamp)
        }
        let scanChange=makeDraft(origin:origin,entityKind:"vehicle_identification_scan",entityID:remoteScan,originVehicleID:originVehicle)
        let scanPersisted=try context.store.localSyncRepository.appendLogicalChange(scanChange)
        let change=makeDraft(origin:origin,entityKind:"vehicle_identifier",entityID:remoteIdentifier,originVehicleID:originVehicle,parentEntityID:remoteScan)
        let persisted=try context.store.localSyncRepository.appendLogicalChange(change)
        let expectedScanDigest=try plannedScanDigest(context.store,scan:scan,vehicle:vehicle,device:peer,stamp:stamp)
        let canonicalDigest=try plannedIdentifierDigest(context.store,identifier:identifier,scan:scan,vehicle:vehicle,lookupDigest:lookupDigest,device:peer,stamp:stamp)
        try context.store.databasePool.write { database in
            try insertAlias(database,id:alias,peer:peer,originVehicle:originVehicle,vehicle:vehicle,generation:1,previous:nil,expectedCount:2,stamp:stamp)
            try insertScanMaterialization(database,id:scanMaterialization,change:scanChange,alias:alias,generation:1,vehicle:vehicle,scan:scan,expectedDigest:expectedScanDigest,stamp:stamp,device:peer)
            try insertLinkedIdentifierMaterialization(database,id:materialization,change:change,alias:alias,vehicle:vehicle,identifier:identifier,scan:scan,parentMaterialization:scanMaterialization,lookupDigest:lookupDigest,canonicalDigest:canonicalDigest,stamp:stamp,device:peer)
            try insertReceipt(database,id:scanReceipt,batch:batch,peer:peer,draft:scanChange,persisted:scanPersisted,stamp:stamp)
            try insertReceipt(database,id:receipt,batch:batch,peer:peer,draft:change,persisted:persisted,stamp:stamp)
        }
        try context.store.localSyncRepository.sealAliasGraphManifest(aliasID:alias,updatedAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.applyInsertedProjection(materializationID:scanMaterialization,receiptID:scanReceipt,appliedAt:Date(),deviceID:peer) { try self.insertScan($0,id:scan,vehicle:vehicle,device:peer,stamp:stamp) }
        try context.store.databasePool.write { try insertIdentifier($0,id:identifier,vehicle:vehicle,scan:scan,lookupDigest:lookupDigest,device:peer,stamp:stamp) }
        #expect(throws:SyncPersistenceError.unavailable) { try context.store.localSyncRepository.applyLinkedIdentifierDuplicate(materializationID:materialization,receiptID:receipt,appliedAt:Date(),deviceID:peer,crashInjection:.afterMaterializationApplied) }
        let rolledBack=try context.store.databasePool.read { database in
            (try String.fetchOne(database,sql:"SELECT materialization_state FROM origin_entity_materializations WHERE materialization_id=?",arguments:[materialization.uuidString.lowercased()]),try String.fetchOne(database,sql:"SELECT apply_state FROM received_changes WHERE receipt_id=?",arguments:[receipt.uuidString.lowercased()]))
        }
        #expect(rolledBack.0=="projected"); #expect(rolledBack.1=="validated")
        try context.store.localSyncRepository.applyLinkedIdentifierDuplicate(materializationID:materialization,receiptID:receipt,appliedAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.markAliasReady(aliasID:alias,readyAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.publishAlias(aliasID:alias,activatedAt:Date(),deviceID:peer)
        let final=try context.store.databasePool.read { database in
            (try String.fetchOne(database,sql:"SELECT apply_state FROM received_changes WHERE receipt_id=?",arguments:[receipt.uuidString.lowercased()]),try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM active_or_local_vehicle_identifiers WHERE identifier_id=?",arguments:[identifier.uuidString.lowercased()]))
        }
        #expect(final.0=="duplicate"); #expect(final.1==1)
    }

    /// unrelated applied親、別Origin、誤materialized ID、secondary／tertiary誤結合をready／active化させません。
    @Test
    func materializationGraphIdentityRemainsImmutableBeforeAndAfterActivePublication() throws {
        let prepared=try makeAppliedAliasGraph()
        defer { prepared.context.fixture.remove() }
        let child=prepared.child.uuidString.lowercased()
        let mutations:[(sql:String,arguments:StatementArguments)] = [
            ("UPDATE origin_entity_materializations SET origin_parent_entity_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET materialized_parent_entity_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET parent_materialization_id=? WHERE materialization_id=?",[child,child]),
            ("UPDATE origin_entity_materializations SET origin_device_identity_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET vehicle_alias_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET graph_generation=graph_generation+1 WHERE materialization_id=?",[child]),
            ("UPDATE origin_entity_materializations SET canonical_vehicle_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET entity_kind='ecu_observation' WHERE materialization_id=?",[child]),
            ("UPDATE origin_entity_materializations SET origin_entity_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET projection_version=projection_version+1 WHERE materialization_id=?",[child]),
            ("UPDATE origin_entity_materializations SET materialized_entity_id=? WHERE materialization_id=?",[UUID().uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET origin_secondary_parent_entity_kind='vehicle_identification_scan',origin_secondary_parent_entity_id=?,secondary_parent_materialization_id=?,materialized_secondary_parent_entity_id=? WHERE materialization_id=?",[prepared.remoteScan.uuidString.lowercased(),child,prepared.scan.uuidString.lowercased(),child]),
            ("UPDATE origin_entity_materializations SET origin_tertiary_parent_entity_kind='vehicle_identification_scan',origin_tertiary_parent_entity_id=?,tertiary_parent_materialization_id=?,materialized_tertiary_parent_entity_id=? WHERE materialization_id=?",[prepared.remoteScan.uuidString.lowercased(),child,prepared.scan.uuidString.lowercased(),child]),
        ]
        for mutation in mutations {
            #expect(throws:(any Error).self) { try prepared.context.store.databasePool.write { try $0.execute(sql:mutation.sql,arguments:mutation.arguments) } }
        }
        try prepared.context.store.localSyncRepository.markAliasReady(aliasID:prepared.alias,readyAt:Date(),deviceID:prepared.peer)
        for mutation in mutations {
            #expect(throws:(any Error).self) { try prepared.context.store.databasePool.write { try $0.execute(sql:mutation.sql,arguments:mutation.arguments) } }
        }
        try prepared.context.store.localSyncRepository.publishAlias(aliasID:prepared.alias,activatedAt:Date(),deviceID:prepared.peer)
        let publishedBefore=try visibleScanIDs(prepared.context.store)
        for mutation in mutations {
            #expect(throws:(any Error).self) { try prepared.context.store.databasePool.write { try $0.execute(sql:mutation.sql,arguments:mutation.arguments) } }
        }
        #expect(try visibleScanIDs(prepared.context.store)==publishedBefore)
    }

    /// Session Transferをmanifest_pendingからverifyingまで正規遷移させます。
    private func advanceSessionToVerifying(_ database:Database,transferID:UUID,stamp:String,device:UUID) throws {
        let id=transferID.uuidString.lowercased(), actor=device.uuidString.lowercased()
        try database.execute(sql:"UPDATE session_transfers SET transfer_state='transferring',transition_step=transition_step+1,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE session_transfer_id=?",arguments:[stamp,actor,id])
        try database.execute(sql:"UPDATE session_transfers SET transfer_state='verifying',transition_step=transition_step+1,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE session_transfer_id=?",arguments:[stamp,actor,id])
    }
    /// Segmentをexpectedからverifiedまで正規遷移させます。
    private func receiveAndVerifySegment(_ database:Database,chunkTransferID:UUID,index:Int,stamp:String) throws {
        let id=chunkTransferID.uuidString.lowercased()
        try database.execute(sql:"UPDATE chunk_transfer_segments SET segment_state='received',transition_step=transition_step+1,received_at=?,updated_at=?,revision=revision+1 WHERE chunk_transfer_id=? AND segment_index=?",arguments:[stamp,stamp,id,index])
        try database.execute(sql:"UPDATE chunk_transfer_segments SET segment_state='verified',transition_step=transition_step+1,verified_at=?,updated_at=?,revision=revision+1 WHERE chunk_transfer_id=? AND segment_index=?",arguments:[stamp,stamp,id,index])
    }
    /// Chunk Transferをreceivingからcatalogedまで正規遷移させます。
    private func advanceChunkToCataloged(_ database:Database,chunkTransferID:UUID,stamp:String) throws {
        let id=chunkTransferID.uuidString.lowercased()
        try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='segments_complete',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[id])
        try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='verified',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[id])
        try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='file_durable',transition_step=transition_step+1,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[id])
        try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='cataloged',transition_step=transition_step+1,staging_relative_path=NULL,cataloged_at=?,revision=revision+1 WHERE chunk_transfer_id=?",arguments:[stamp,id])
    }
    /// Wrapped Keyをreceivedからappliedまで正規遷移させます。
    private func verifyAndApplyWrappedKey(_ database:Database,keyEnvelopeID:UUID,stamp:String) throws {
        let id=keyEnvelopeID.uuidString.lowercased()
        try database.execute(sql:"UPDATE wrapped_key_receipts SET receipt_state='verified',transition_step=transition_step+1,revision=revision+1 WHERE key_envelope_id=?",arguments:[id])
        try database.execute(sql:"UPDATE wrapped_key_receipts SET receipt_state='applied',transition_step=transition_step+1,applied_keychain_reference_id=?,applied_at=?,revision=revision+1 WHERE key_envelope_id=?",arguments:[UUID().uuidString.lowercased(),stamp,id])
    }

    /// 一時DBとMigration済みStoreを作ります。
    private func makeContext() throws -> (fixture:TemporaryVehicleDatabase,store:GRDBVehicleIdentityStore) { let fixture=try TemporaryVehicleDatabase(); guard case .available(let store)=GRDBVehicleIdentityStore.open(at:fixture.url,userScopeID:VehicleIdentityTestFixtures.scopeID,activeDigestKeyVersion:1,createdAt:VehicleIdentityTestFixtures.recordedAt) else { throw SyncPersistenceError.unavailable }; return(fixture,store) }
    /// Durable ACKの各不一致fixture種別です。
    private enum DurableMismatch: CaseIterable, Equatable {
        case session
        case stream
        case sequence
        case catalogDigest
        case missingStream
        case missingEpoch
        case missingGap
        case keySession
        case keyChunk
    }
    /// Catalog済みSession Transferと必要なFake業務目録を作ります。
    private func makeCatalogedTransfer(mismatch:DurableMismatch?) throws -> (context:(fixture:TemporaryVehicleDatabase,store:GRDBVehicleIdentityStore),transfer:UUID,peer:UUID) {
        let context=try makeContext(), peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let transfer=UUID(), session=UUID(), stream=UUID(), chunk=UUID(), epoch=UUID(), stamp=timestamp(), device=peer.uuidString.lowercased()
        let ciphertextDigest=Data(repeating:6,count:32), catalogDigest=Data(repeating:9,count:32)
        try context.store.databasePool.write { database in
            let local:String=try String.fetchOne(database,sql:"SELECT device_identity_id FROM local_device_identity")!
            try database.execute(sql:"INSERT INTO acquisition_sessions(user_scope_id,session_id,vehicle_id,vehicle_binding_state,capture_state,disposition_state,integrity_state,end_reason_code,started_at_utc,ended_at_utc,reviewed_at_utc,disposition_requested_at_utc,disposition_completed_at_utc,created_by_device_id,record_revision,updated_at_utc,updated_by_device_id) VALUES(?,?,NULL,'unassigned_unidentified','ended_cleanly','pending_decision','verified','user_stop',?,?,NULL,NULL,NULL,?,1,?,?)",arguments:[scope,session.uuidString.lowercased(),stamp,stamp,device,stamp,device])
            try database.execute(sql:"INSERT INTO acquisition_streams(user_scope_id,stream_id,session_id,stream_kind,adapter_role,adapter_reference_id,connection_instance_id,stream_state,started_at_utc,ended_at_utc,next_record_sequence,next_chunk_sequence,record_revision,updated_at_utc) VALUES(?,?,?,'obd_pid','primary','fake',?,'stopped',?,?,1,1,1,?)",arguments:[scope,stream.uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),stamp,stamp,stamp])
            try database.execute(sql:"INSERT INTO clock_epochs(user_scope_id,clock_epoch_id,session_id,process_instance_id,device_id,monotonic_clock_kind,wall_clock_anchor_utc,anchor_uncertainty_ns,started_at_utc,ended_at_utc,revision) VALUES(?,?,?,?,?,'continuous_host_time',?,0,?,?,1)",arguments:[scope,epoch.uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),device,stamp,stamp,stamp])
            try database.execute(sql:"INSERT INTO log_chunks(user_scope_id,chunk_id,session_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,record_format_version,compression_format_version,encryption_format_version,key_version,ciphertext_digest,catalog_digest,relative_path,storage_state,revision,created_at_utc,updated_at_utc) VALUES(?,?,?,?,0,?,0,0,0,0,1,4,4,4,1,1,1,1,?,?,'chunks/test','available',1,?,?)",arguments:[scope,chunk.uuidString.lowercased(),session.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),ciphertextDigest,catalogDigest,stamp,stamp])
            let manifest=try MaterializedEntityDigestV1.sessionManifestDigest(database:database,scope:scope,sessionID:session.uuidString.lowercased())
            try database.execute(sql:"INSERT INTO session_transfers(user_scope_id,session_transfer_id,batch_id,session_id,manifest_digest,expected_chunk_count,expected_ciphertext_bytes,transfer_state,durable_ack_id,durable_ack_binding_digest,durable_at,acknowledged_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,4,'manifest_pending',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,transfer.uuidString.lowercased(),batch.uuidString.lowercased(),session.uuidString.lowercased(),manifest,stamp,device,stamp,device])
            try advanceSessionToVerifying(database, transferID:transfer, stamp:stamp, device:peer)
            let transferSession = mismatch == .session ? UUID().uuidString.lowercased() : session.uuidString.lowercased()
            let transferStream = mismatch == .stream ? UUID().uuidString.lowercased() : stream.uuidString.lowercased()
            let transferSequence = mismatch == .sequence ? 1 : 0
            let transferCatalog = mismatch == .catalogDigest ? Data(repeating:88,count:32) : catalogDigest
            let chunkTransfer=UUID()
            try database.execute(sql:"INSERT INTO chunk_transfers(user_scope_id,chunk_transfer_id,session_transfer_id,session_id,chunk_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,ciphertext_digest,catalog_digest,record_format_version,compression_format_version,encryption_format_version,key_version,catalog_relative_path,catalog_storage_state,catalog_revision,catalog_created_at_utc,catalog_updated_at_utc,transfer_state,staging_relative_path,cataloged_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,?,0,0,0,0,1,4,4,4,?,?,1,1,1,1,'chunks/test','available',1,?,?,'pending',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),transfer.uuidString.lowercased(),transferSession,chunk.uuidString.lowercased(),transferStream,transferSequence,epoch.uuidString.lowercased(),ciphertextDigest,transferCatalog,stamp,stamp,stamp,device,stamp,device])
            try database.execute(sql:"UPDATE chunk_transfers SET transfer_state='receiving',transition_step=transition_step+1,staging_relative_path='staging/chunk',revision=revision+1 WHERE chunk_transfer_id=?",arguments:[chunkTransfer.uuidString.lowercased()])
            try database.execute(sql:"INSERT INTO chunk_transfer_segments(user_scope_id,chunk_transfer_id,segment_index,byte_offset,byte_length,segment_digest,segment_state,received_at,verified_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,0,0,4,?,'expected',NULL,NULL,?,?,?,?,1)",arguments:[scope,chunkTransfer.uuidString.lowercased(),Data(repeating:7,count:32),stamp,device,stamp,device])
            try receiveAndVerifySegment(database, chunkTransferID:chunkTransfer, index:0, stamp:stamp)
            try advanceChunkToCataloged(database, chunkTransferID:chunkTransfer, stamp:stamp)
            let keySession = mismatch == .keySession ? UUID().uuidString.lowercased() : session.uuidString.lowercased()
            let keyChunk = mismatch == .keyChunk ? UUID().uuidString.lowercased() : chunk.uuidString.lowercased()
            let keyEnvelope=UUID()
            try database.execute(sql:"INSERT INTO wrapped_key_receipts(user_scope_id,key_envelope_id,sender_identity_id,sender_signing_key_version,recipient_identity_id,recipient_agreement_key_version,trust_generation,key_purpose,wrapped_key_version,bound_session_id,bound_chunk_id,nonce_digest,envelope_digest,envelope_ciphertext,receipt_state,applied_keychain_reference_id,applied_at,quarantine_id,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,1,?,1,1,'session_chunk',1,?,?,?,?,?,'received',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,keyEnvelope.uuidString.lowercased(),device,local,keySession,keyChunk,Data(repeating:41,count:32),Data(repeating:42,count:32),Data([1]),stamp,device,stamp,device])
            try verifyAndApplyWrappedKey(database, keyEnvelopeID:keyEnvelope, stamp:stamp)
            if mismatch == .missingStream {
                try database.execute(sql:"INSERT INTO acquisition_streams(user_scope_id,stream_id,session_id,stream_kind,adapter_role,adapter_reference_id,connection_instance_id,stream_state,started_at_utc,ended_at_utc,next_record_sequence,next_chunk_sequence,record_revision,updated_at_utc) VALUES(?,?,?,'raw_can','secondary','fake-secondary',?,'stopped',?,?,0,0,1,?)",arguments:[scope,UUID().uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),stamp,stamp,stamp])
            } else if mismatch == .missingEpoch {
                try database.execute(sql:"INSERT INTO clock_epochs(user_scope_id,clock_epoch_id,session_id,process_instance_id,device_id,monotonic_clock_kind,wall_clock_anchor_utc,anchor_uncertainty_ns,started_at_utc,ended_at_utc,revision) VALUES(?,?,?,?,?,'continuous_host_time',?,0,?,?,1)",arguments:[scope,UUID().uuidString.lowercased(),session.uuidString.lowercased(),UUID().uuidString.lowercased(),device,stamp,stamp,stamp])
            } else if mismatch == .missingGap {
                try database.execute(sql:"INSERT INTO acquisition_gaps(user_scope_id,gap_id,session_id,stream_id,reason_code,detection_method,start_boundary_certainty,start_clock_epoch_id,start_monotonic_ns,start_utc,end_clock_epoch_id,end_monotonic_ns,end_utc,end_boundary_certainty,first_missing_sequence,missing_record_count,revision,created_at_utc) VALUES(?,?,?,?,'user_paused','user_action','confirmed',?,0,?, ?,1,?,'confirmed',1,1,2,?)",arguments:[scope,UUID().uuidString.lowercased(),session.uuidString.lowercased(),stream.uuidString.lowercased(),epoch.uuidString.lowercased(),stamp,epoch.uuidString.lowercased(),stamp,stamp])
            }
        }
        return(context,transfer,peer)
    }
    /// ready直前まで正しく適用済みの二階層Alias graphを作ります。
    private func makeAppliedAliasGraph() throws -> (context:(fixture:TemporaryVehicleDatabase,store:GRDBVehicleIdentityStore),alias:UUID,parent:UUID,child:UUID,peer:UUID,remoteScan:UUID,scan:UUID) {
        let context=try makeContext(), peer=try provisionFakePeer(context.store), batch=try insertBatch(context.store,peer:peer,direction:"receive")
        let origin=UUID(), vehicle=UUID(), scan=UUID(), identifier=UUID(), originVehicle=UUID(), remoteScan=UUID(), remoteIdentifier=UUID(), alias=UUID(), parent=UUID(), child=UUID(), parentReceipt=UUID(), childReceipt=UUID(), stamp=timestamp(), lookupDigest=Data(repeating:71,count:32)
        try context.store.databasePool.write { try insertVehicle($0,id:vehicle,device:peer,stamp:stamp) }
        let parentChange=makeDraft(origin:origin,entityKind:"vehicle_identification_scan",entityID:remoteScan,originVehicleID:originVehicle)
        let parentPersisted=try context.store.localSyncRepository.appendLogicalChange(parentChange)
        let childChange=makeDraft(origin:origin,entityKind:"vehicle_identifier",entityID:remoteIdentifier,originVehicleID:originVehicle,parentEntityID:remoteScan)
        let childPersisted=try context.store.localSyncRepository.appendLogicalChange(childChange)
        let scanDigest=try plannedScanDigest(context.store,scan:scan,vehicle:vehicle,device:peer,stamp:stamp)
        let identifierDigest=try plannedIdentifierDigest(context.store,identifier:identifier,scan:scan,vehicle:vehicle,lookupDigest:lookupDigest,device:peer,stamp:stamp)
        try context.store.databasePool.write { database in
            try insertAlias(database,id:alias,peer:peer,originVehicle:originVehicle,vehicle:vehicle,generation:1,previous:nil,expectedCount:2,stamp:stamp)
            try insertScanMaterialization(database,id:parent,change:parentChange,alias:alias,generation:1,vehicle:vehicle,scan:scan,expectedDigest:scanDigest,stamp:stamp,device:peer)
            try insertLinkedIdentifierMaterialization(database,id:child,change:childChange,alias:alias,vehicle:vehicle,identifier:identifier,scan:scan,parentMaterialization:parent,lookupDigest:lookupDigest,canonicalDigest:identifierDigest,stamp:stamp,device:peer)
            try insertReceipt(database,id:parentReceipt,batch:batch,peer:peer,draft:parentChange,persisted:parentPersisted,stamp:stamp)
            try insertReceipt(database,id:childReceipt,batch:batch,peer:peer,draft:childChange,persisted:childPersisted,stamp:stamp)
        }
        try context.store.localSyncRepository.sealAliasGraphManifest(aliasID:alias,updatedAt:Date(),deviceID:peer)
        try context.store.localSyncRepository.applyInsertedProjection(materializationID:parent,receiptID:parentReceipt,appliedAt:Date(),deviceID:peer) { try self.insertScan($0,id:scan,vehicle:vehicle,device:peer,stamp:stamp) }
        try context.store.databasePool.write { try insertIdentifier($0,id:identifier,vehicle:vehicle,scan:scan,lookupDigest:lookupDigest,device:peer,stamp:stamp) }
        try context.store.localSyncRepository.applyLinkedIdentifierDuplicate(materializationID:child,receiptID:childReceipt,appliedAt:Date(),deviceID:peer)
        return(context,alias,parent,child,peer,remoteScan,scan)
    }
    /// Fake codecが作るVersion 1 Logical Changeを返します。
    private func makeDraft(origin:UUID,entityKind:String="vehicle_identification_scan",entityID:UUID=UUID(),originVehicleID:UUID=UUID(),parentEntityID:UUID?=nil) -> SyncLogicalChangeDraft { SyncLogicalChangeDraft(logicalChangeID:UUID(),originDeviceIdentityID:origin,originSigningKeyVersion:1,originSigningPublicKey:Data([1]),originSigningKeyFingerprint:Data(repeating:1,count:32),originChangeID:UUID(),streamKind:.immutableIdentity,entityKind:entityKind,entityID:entityID,originVehicleID:originVehicleID,originParentEntityKind:entityKind=="vehicle_identifier" ? "vehicle_identification_scan":"vehicle",originParentEntityID:parentEntityID ?? originVehicleID,entitySchemaVersion:1,operationKind:.upsertImmutable,baseRevision:nil,resultRevision:1,contentDigest:Data(repeating:2,count:32),originEnvelopeCiphertext:Data([3]),originSignature:Data([4]),originMembershipProofDigest:Data(repeating:5,count:32),originCreatedAt:Date(),createdByDeviceID:origin) }
    /// establishedなlocal identityとpaired／trusted Fake Peerを作ります。
    private func provisionFakePeer(_ store:GRDBVehicleIdentityStore) throws -> UUID { let local=UUID(),peer=UUID(),stamp=timestamp(); try store.databasePool.write { database in
        try database.execute(sql:"INSERT INTO local_device_identity(scope_row_id,user_scope_id,device_identity_id,device_role,device_identity_version,signing_key_version,signing_public_key,signing_key_fingerprint,signing_keychain_reference_id,key_agreement_key_version,key_agreement_public_key,key_agreement_key_fingerprint,key_agreement_keychain_reference_id,tls_identity_key_version,tls_identity_public_key,tls_identity_key_fingerprint,tls_certificate_fingerprint,tls_identity_keychain_reference_id,membership_state,membership_version,membership_credential_digest,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(1,?,?,'iphone',1,1,?,?,?,1,?,?,?,1,?,?,?,?, 'established',1,NULL,?,?,?,?,1)",arguments:[scope,local.uuidString.lowercased(),Data([1]),Data(repeating:11,count:32),UUID().uuidString.lowercased(),Data([2]),Data(repeating:12,count:32),UUID().uuidString.lowercased(),Data([3]),Data(repeating:13,count:32),Data(repeating:14,count:32),UUID().uuidString.lowercased(),stamp,local.uuidString.lowercased(),stamp,local.uuidString.lowercased()])
        try database.execute(sql:"INSERT INTO paired_devices(user_scope_id,peer_identity_id,device_role,device_identity_version,signing_key_version,signing_public_key,signing_key_fingerprint,key_agreement_key_version,key_agreement_public_key,key_agreement_key_fingerprint,tls_identity_key_version,tls_identity_public_key,tls_identity_key_fingerprint,tls_certificate_fingerprint,peer_pin_keychain_reference_id,membership_verification_state,membership_version,pairing_state,paired_at,unpaired_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'mac',1,1,?,?,1,?,?,1,?,?,?,?, 'verified',1,'paired',?,NULL,?,?,?,?,1)",arguments:[scope,peer.uuidString.lowercased(),Data([4]),Data(repeating:21,count:32),Data([5]),Data(repeating:22,count:32),Data([6]),Data(repeating:23,count:32),Data(repeating:24,count:32),UUID().uuidString.lowercased(),stamp,stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
        try database.execute(sql:"INSERT INTO device_trust_records(user_scope_id,peer_identity_id,trust_state,trust_generation,trusted_at,suspended_at,revoked_at,reason_code,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,'trusted',1,?,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,peer.uuidString.lowercased(),stamp,stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()])
    }; return peer }
    /// Fake peer用Batchを作ります。
    private func insertBatch(_ store:GRDBVehicleIdentityStore,peer:UUID,direction:String) throws -> UUID { let id=UUID(),stamp=timestamp(); try store.databasePool.write { try $0.execute(sql:"INSERT INTO sync_batches(user_scope_id,batch_id,transfer_id,peer_identity_id,direction,sync_protocol_version,capability_digest,batch_state,last_error_code,diagnostic_id,completed_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,1,?,'applying',NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,id.uuidString.lowercased(),UUID().uuidString.lowercased(),peer.uuidString.lowercased(),direction,Data(repeating:31,count:32),stamp,peer.uuidString.lowercased(),stamp,peer.uuidString.lowercased()]) }; return id }
    /// 固定scope文字列です。
    private var scope:String { VehicleIdentityTestFixtures.scopeID.uuidString.lowercased() }
    /// テスト用固定書式時刻です。
    private func timestamp() -> String { GRDBVehicleDateCodec.string(from:Date()) }
    /// active graphから公開されるScan IDを返します。
    private func visibleScanIDs(_ store:GRDBVehicleIdentityStore) throws -> [String] { try store.databasePool.read { try String.fetchAll($0,sql:"SELECT scan_id FROM active_or_local_vehicle_identification_scans ORDER BY scan_id") } }
    /// INSERT予定Scanをrollback transactionでcanonical encodeし、業務行を残さずexpected digestを得ます。
    private func plannedScanDigest(_ store:GRDBVehicleIdentityStore,scan:UUID,vehicle:UUID,device:UUID,stamp:String) throws -> Data { var result:Data!; try store.databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) { try insertScan(database,id:scan,vehicle:vehicle,device:device,stamp:stamp); result=try MaterializedEntityDigestV1.digest(database:database,scope:scope,entityKind:"vehicle_identification_scan",entityID:scan.uuidString.lowercased()); return .rollback } }; return result }
    /// INSERT予定Identifierと親Scanをrollback transactionでcanonical encodeします。
    private func plannedIdentifierDigest(_ store:GRDBVehicleIdentityStore,identifier:UUID,scan:UUID,vehicle:UUID,lookupDigest:Data,device:UUID,stamp:String) throws -> Data { var result:Data!; try store.databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) { try insertScan(database,id:scan,vehicle:vehicle,device:device,stamp:stamp); try insertIdentifier(database,id:identifier,vehicle:vehicle,scan:scan,lookupDigest:lookupDigest,device:device,stamp:stamp); result=try MaterializedEntityDigestV1.digest(database:database,scope:scope,entityKind:"vehicle_identifier",entityID:identifier.uuidString.lowercased()); return .rollback } }; return result }
    /// Alias用canonical Vehicleを作ります。
    private func insertVehicle(_ database:Database,id:UUID,device:UUID,stamp:String) throws { let d=device.uuidString.lowercased(); try database.execute(sql:"INSERT INTO vehicles(user_scope_id,vehicle_id,display_name_ciphertext,display_name_key_version,lifecycle_state,record_revision,display_name_revision,display_name_updated_at,display_name_updated_by_device_id,lifecycle_revision,lifecycle_updated_at,lifecycle_updated_by_device_id,archived_at,created_at,created_by_device_id,updated_at,updated_by_device_id) VALUES(?,?,NULL,NULL,'active',1,0,NULL,NULL,1,?,?,NULL,?,?,?,?)",arguments:[scope,id.uuidString.lowercased(),stamp,d,stamp,d,stamp,d]) }
    /// preparing Alias graphをplaceholder Manifest付きで作り、後でRepositoryに封印させます。
    private func insertAlias(_ database:Database,id:UUID,peer:UUID,originVehicle:UUID,vehicle:UUID,generation:Int,previous:UUID?,expectedCount:Int,stamp:String) throws { let device=peer.uuidString.lowercased(); try database.execute(sql:"INSERT INTO vehicle_id_aliases(user_scope_id,vehicle_alias_id,source_peer_identity_id,source_vehicle_id,canonical_vehicle_id,alias_revision,previous_alias_id,match_basis_kind,basis_digest,graph_source_frontier,graph_manifest_digest,expected_materialization_count,mapping_state,ready_at,activated_at,superseded_by_alias_id,superseded_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,'same_entity_id',NULL,?,?,?,'preparing',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,id.uuidString.lowercased(),peer.uuidString.lowercased(),originVehicle.uuidString.lowercased(),vehicle.uuidString.lowercased(),generation,previous?.uuidString.lowercased(),Data([1,UInt8(generation)]),Data(repeating:0,count:32),expectedCount,stamp,device,stamp,device]) }
    /// Logical Changeと一致するvalidated Receiptを作ります。
    private func insertReceipt(_ database:Database,id:UUID,batch:UUID,peer:UUID,draft:SyncLogicalChangeDraft,persisted:PersistedSyncLogicalChange,stamp:String) throws { let device=peer.uuidString.lowercased(); try database.execute(sql:"INSERT INTO received_changes(user_scope_id,receipt_id,source_peer_identity_id,batch_id,logical_change_id,origin_device_identity_id,origin_change_id,stream_kind,change_sequence,previous_chain_digest,chain_digest,entity_kind,entity_id,entity_schema_version,content_digest,relay_hop_count,apply_state,applied_revision,conflict_id,quarantine_id,applied_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'validated',NULL,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,id.uuidString.lowercased(),peer.uuidString.lowercased(),batch.uuidString.lowercased(),draft.logicalChangeID.uuidString.lowercased(),draft.originDeviceIdentityID.uuidString.lowercased(),draft.originChangeID.uuidString.lowercased(),draft.streamKind.rawValue,persisted.sequence,persisted.previousChainDigest,persisted.chainDigest,draft.entityKind,draft.entityID.uuidString.lowercased(),draft.entitySchemaVersion,draft.contentDigest,1,stamp,device,stamp,device]) }
    /// active-or-local View検証用Scanを作ります。
    private func insertScan(_ database:Database,id:UUID,vehicle:UUID,device:UUID,stamp:String) throws { let d=device.uuidString.lowercased(); try database.execute(sql:"INSERT INTO vehicle_identification_scans(user_scope_id,scan_id,vehicle_id,obd_connection_id,transport_kind,diagnostic_protocol_kind,adapter_reference_id,decoder_version,normalization_version,scan_status,decode_state,identity_validation_state,termination_reason_code,started_at,finished_at,revision,created_at,created_by_device_id,updated_at,updated_by_device_id) VALUES(?,?,?,?, 'fake','fake','fake','1','1','completed','decoded','valid',NULL,?,?,1,?,?,?,?)",arguments:[scope,id.uuidString.lowercased(),vehicle.uuidString.lowercased(),id.uuidString.lowercased(),stamp,stamp,stamp,d,stamp,d]) }
    /// linked duplicate試験用の既存canonical Identifierを作ります。
    private func insertIdentifier(_ database:Database,id:UUID,vehicle:UUID,scan:UUID,lookupDigest:Data,device:UUID,stamp:String) throws { let d=device.uuidString.lowercased(); try database.execute(sql:"INSERT INTO vehicle_identifiers(user_scope_id,identifier_id,vehicle_id,identifier_kind,normalized_value_ciphertext,encryption_key_version,lookup_digest,digest_key_version,source_scan_id,revision,created_at,created_by_device_id,updated_at,updated_by_device_id) VALUES(?,?,?,'vin',?,1,?,1,?,1,?,?,?,?)",arguments:[scope,id.uuidString.lowercased(),vehicle.uuidString.lowercased(),Data(repeating:1,count:29),lookupDigest,scan.uuidString.lowercased(),stamp,d,stamp,d]) }
    /// Scanのinserted projection履歴をpreparing graphへ追加します。
    private func insertScanMaterialization(_ database:Database,id:UUID,change:SyncLogicalChangeDraft,alias:UUID,generation:Int,vehicle:UUID,scan:UUID,expectedDigest:Data,stamp:String,device:UUID) throws { let d=device.uuidString.lowercased(); try database.execute(sql:"INSERT INTO origin_entity_materializations(user_scope_id,materialization_id,logical_change_id,origin_device_identity_id,origin_change_id,entity_kind,origin_entity_id,origin_vehicle_id,origin_parent_entity_kind,origin_parent_entity_id,origin_entity_version,origin_content_digest,origin_envelope_storage,vehicle_alias_id,graph_generation,projection_version,canonical_vehicle_id,parent_materialization_id,materialized_parent_entity_id,origin_secondary_parent_entity_kind,origin_secondary_parent_entity_id,secondary_parent_materialization_id,materialized_secondary_parent_entity_id,origin_tertiary_parent_entity_kind,origin_tertiary_parent_entity_id,tertiary_parent_materialization_id,materialized_tertiary_parent_entity_id,materialization_result_kind,materialized_identifier_kind,materialized_identifier_digest_key_version,materialized_identifier_lookup_digest,materialized_content_digest,materialized_entity_id,materialization_state,relay_eligibility,received_at,applied_at,superseded_by_materialization_id,superseded_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,?, 'vehicle',?,1,?,'logical_change_ciphertext',?,?,1,?,NULL,?,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'inserted_projection',NULL,NULL,NULL,?,?,'projected','metadata_relay_allowed',?,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,id.uuidString.lowercased(),change.logicalChangeID.uuidString.lowercased(),change.originDeviceIdentityID.uuidString.lowercased(),change.originChangeID.uuidString.lowercased(),change.entityKind,change.entityID.uuidString.lowercased(),change.originVehicleID!.uuidString.lowercased(),change.originVehicleID!.uuidString.lowercased(),change.contentDigest,alias.uuidString.lowercased(),generation,vehicle.uuidString.lowercased(),vehicle.uuidString.lowercased(),expectedDigest,scan.uuidString.lowercased(),stamp,stamp,d,stamp,d]) }
    /// 既存Identifierへ収束するlinked duplicate Materializationを作ります。
    private func insertLinkedIdentifierMaterialization(_ database:Database,id:UUID,change:SyncLogicalChangeDraft,alias:UUID,vehicle:UUID,identifier:UUID,scan:UUID,parentMaterialization:UUID,lookupDigest:Data,canonicalDigest:Data,stamp:String,device:UUID) throws { let d=device.uuidString.lowercased(); try database.execute(sql:"INSERT INTO origin_entity_materializations(user_scope_id,materialization_id,logical_change_id,origin_device_identity_id,origin_change_id,entity_kind,origin_entity_id,origin_vehicle_id,origin_parent_entity_kind,origin_parent_entity_id,origin_entity_version,origin_content_digest,origin_envelope_storage,vehicle_alias_id,graph_generation,projection_version,canonical_vehicle_id,parent_materialization_id,materialized_parent_entity_id,origin_secondary_parent_entity_kind,origin_secondary_parent_entity_id,secondary_parent_materialization_id,materialized_secondary_parent_entity_id,origin_tertiary_parent_entity_kind,origin_tertiary_parent_entity_id,tertiary_parent_materialization_id,materialized_tertiary_parent_entity_id,materialization_result_kind,materialized_identifier_kind,materialized_identifier_digest_key_version,materialized_identifier_lookup_digest,materialized_content_digest,materialized_entity_id,materialization_state,relay_eligibility,received_at,applied_at,superseded_by_materialization_id,superseded_at,created_at,created_by_device_id,updated_at,updated_by_device_id,revision) VALUES(?,?,?,?,?,?,?,?, 'vehicle_identification_scan',?,1,?,'logical_change_ciphertext',?,1,1,?,?,?,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'linked_existing_duplicate','vin',1,?,?,?,'projected','metadata_relay_allowed',?,NULL,NULL,NULL,?,?,?,?,1)",arguments:[scope,id.uuidString.lowercased(),change.logicalChangeID.uuidString.lowercased(),change.originDeviceIdentityID.uuidString.lowercased(),change.originChangeID.uuidString.lowercased(),change.entityKind,change.entityID.uuidString.lowercased(),change.originVehicleID!.uuidString.lowercased(),change.originParentEntityID!.uuidString.lowercased(),change.contentDigest,alias.uuidString.lowercased(),vehicle.uuidString.lowercased(),parentMaterialization.uuidString.lowercased(),scan.uuidString.lowercased(),lookupDigest,canonicalDigest,identifier.uuidString.lowercased(),stamp,stamp,d,stamp,d]) }
}
