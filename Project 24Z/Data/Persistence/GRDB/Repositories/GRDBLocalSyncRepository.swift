import Foundation
import GRDB

/// GRDB上で同期台帳の短いatomic transactionだけを実行します。
final class GRDBLocalSyncRepository: LocalSyncRepository {
    /// atomic処理のrollback性だけをテストする内部Crash pointです。
    enum CrashInjectionPoint {
        /// Crashを注入しません。
        case none
        /// 業務行INSERT直後に失敗します。
        case afterBusinessInsert
        /// Materialization更新直後、Receipt更新前に失敗します。
        case afterMaterializationApplied
        /// 旧Aliasをsuperseded化した直後に失敗します。
        case afterOldAliasSuperseded
    }

    private let databasePool: DatabasePool
    private let scopeString: String

    /// 検査済みユーザー別PoolへRepositoryを束縛します。
    /// - Parameters:
    ///   - databasePool: v3 MigrationとSQL functionが準備済みのPool。
    ///   - userScopeID: `database_scope`と一致するscope。
    init(databasePool: DatabasePool, userScopeID: UUID) { self.databasePool=databasePool; scopeString=userScopeID.uuidString.lowercased() }

    /// Sequence末尾取得、digest計算、INSERTを同じ即時transactionで行います。
    func appendLogicalChange(_ draft: SyncLogicalChangeDraft) throws -> PersistedSyncLogicalChange {
        guard draft.originSigningKeyVersion>=1, draft.entitySchemaVersion>=1, draft.resultRevision>=1, draft.originSigningKeyFingerprint.count==32, draft.contentDigest.count==32, draft.originMembershipProofDigest.count==32, !draft.originEnvelopeCiphertext.isEmpty, !draft.originSignature.isEmpty, (draft.originParentEntityKind==nil)==(draft.originParentEntityID==nil), (draft.originSecondaryParentEntityKind==nil)==(draft.originSecondaryParentEntityID==nil), (draft.originTertiaryParentEntityKind==nil)==(draft.originTertiaryParentEntityID==nil) else { throw SyncPersistenceError.invalidRequest }
        do {
            return try databasePool.writeWithoutTransaction { database in
                var result: PersistedSyncLogicalChange!
                try database.inTransaction(.immediate) {
                    guard try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM local_device_identity WHERE user_scope_id=? AND membership_state='established'",arguments:[scopeString])==1 else { throw SyncPersistenceError.blocked }
                    let previous = try Row.fetchOne(database,sql:"SELECT origin_change_id,chain_digest,change_sequence FROM logical_sync_changes WHERE user_scope_id=? AND origin_device_identity_id=? AND stream_kind=? ORDER BY change_sequence DESC LIMIT 1",arguments:[scopeString,uuid(draft.originDeviceIdentityID),draft.streamKind.rawValue])
                    let sequence = (previous?["change_sequence"] as Int64?).map{$0+1} ?? 0
                    let previousID: String? = previous?["origin_change_id"]
                    let previousDigest: Data? = previous?["chain_digest"]
                    let chainArguments: StatementArguments = [uuid(draft.originDeviceIdentityID),draft.originSigningKeyVersion,draft.originSigningKeyFingerprint,draft.streamKind.rawValue,sequence,uuid(draft.originChangeID),draft.entityKind,uuid(draft.entityID),draft.originVehicleID.map(uuid),draft.originParentEntityKind,draft.originParentEntityID.map(uuid),draft.originSecondaryParentEntityKind,draft.originSecondaryParentEntityID.map(uuid),draft.originTertiaryParentEntityKind,draft.originTertiaryParentEntityID.map(uuid),draft.entitySchemaVersion,draft.contentDigest,previousDigest]
                    guard let chain = try Data.fetchOne(database,sql:"SELECT sync_chain_digest_v1(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",arguments:chainArguments) else { throw SyncPersistenceError.unavailable }
                    try database.execute(sql:"INSERT INTO logical_sync_changes(user_scope_id,logical_change_id,origin_device_identity_id,origin_signing_key_version,origin_signing_public_key,origin_signing_key_fingerprint,origin_change_id,stream_kind,change_sequence,previous_change_id,previous_chain_digest,chain_digest,entity_kind,entity_id,origin_vehicle_id,origin_parent_entity_kind,origin_parent_entity_id,origin_secondary_parent_entity_kind,origin_secondary_parent_entity_id,origin_tertiary_parent_entity_kind,origin_tertiary_parent_entity_id,entity_schema_version,operation_kind,base_revision,result_revision,content_digest,origin_envelope_ciphertext,origin_signature,origin_membership_proof_digest,creation_revision,origin_created_at,created_at,created_by_device_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?)",arguments:[scopeString,uuid(draft.logicalChangeID),uuid(draft.originDeviceIdentityID),draft.originSigningKeyVersion,draft.originSigningPublicKey,draft.originSigningKeyFingerprint,uuid(draft.originChangeID),draft.streamKind.rawValue,sequence,previousID,previousDigest,chain,draft.entityKind,uuid(draft.entityID),draft.originVehicleID.map(uuid),draft.originParentEntityKind,draft.originParentEntityID.map(uuid),draft.originSecondaryParentEntityKind,draft.originSecondaryParentEntityID.map(uuid),draft.originTertiaryParentEntityKind,draft.originTertiaryParentEntityID.map(uuid),draft.entitySchemaVersion,draft.operationKind.rawValue,draft.baseRevision,draft.resultRevision,draft.contentDigest,draft.originEnvelopeCiphertext,draft.originSignature,draft.originMembershipProofDigest,timestamp(draft.originCreatedAt),timestamp(draft.originCreatedAt),uuid(draft.createdByDeviceID)])
                    result=PersistedSyncLogicalChange(logicalChangeID:draft.logicalChangeID,sequence:sequence,previousChangeID:previousID.flatMap(UUID.init(uuidString:)),previousChainDigest:previousDigest,chainDigest:chain)
                    return .commit
                }
                return result
            }
        } catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.conflict } catch { throw SyncPersistenceError.unavailable }
    }

    /// Cursor Triggerへ次の一件のIDとdigestだけを渡して前進します。
    func advanceCursor(peerIdentityID: UUID, direction: String, originDeviceIdentityID: UUID, streamKind: SyncLogicalChangeDraft.StreamKind, updatedAt: Date, deviceID: UUID) throws {
        guard direction=="sent" || direction=="received" else { throw SyncPersistenceError.invalidRequest }
        do { try databasePool.write { database in
            guard let row=try Row.fetchOne(database,sql:"SELECT c.origin_change_id,c.chain_digest FROM peer_sync_cursors p JOIN logical_sync_changes c ON c.user_scope_id=p.user_scope_id AND c.origin_device_identity_id=p.origin_device_identity_id AND c.stream_kind=p.stream_kind AND c.change_sequence=p.next_expected_sequence WHERE p.user_scope_id=? AND p.peer_identity_id=? AND p.direction=? AND p.origin_device_identity_id=? AND p.stream_kind=?",arguments:[scopeString,uuid(peerIdentityID),direction,uuid(originDeviceIdentityID),streamKind.rawValue]) else { throw SyncPersistenceError.blocked }
            try database.execute(sql:"UPDATE peer_sync_cursors SET next_expected_sequence=next_expected_sequence+1,last_change_id=?,last_chain_digest=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND peer_identity_id=? AND direction=? AND origin_device_identity_id=? AND stream_kind=?",arguments:[row["origin_change_id"] as String,row["chain_digest"] as Data,timestamp(updatedAt),uuid(deviceID),scopeString,uuid(peerIdentityID),direction,uuid(originDeviceIdentityID),streamKind.rawValue])
        }} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable }
    }

    /// 業務行INSERT、canonical読戻し、MaterializationとReceiptの確定を同じ即時transactionで行います。
    ///
    /// `insertBusinessRow`はData層のEntity decoderが作るINSERTだけを受ける内部境界です。Digestは受け取らず、
    /// Repository自身がINSERT後のraw業務行から再計算します。
    /// - Parameters:
    ///   - materializationID: `inserted_projection`の予約済みMaterialization ID。
    ///   - receiptID: 同じLogical Changeのvalidated Receipt ID。
    ///   - appliedAt: 永続適用時刻。
    ///   - deviceID: 適用端末ID。
    ///   - crashInjection: rollback試験専用Crash point。
    ///   - insertBusinessRow: 同じGRDB transactionへ業務行をINSERTするData層処理。
    /// - Throws: Digest、親、Receipt、SQL制約の不一致。
    func applyInsertedProjection(
        materializationID: UUID,
        receiptID: UUID,
        appliedAt: Date,
        deviceID: UUID,
        crashInjection: CrashInjectionPoint = .none,
        insertBusinessRow: @escaping (Database) throws -> Void
    ) throws {
        try applyAtomically(
            materializationID: materializationID,
            receiptID: receiptID,
            terminalReceiptState: "applied",
            appliedAt: appliedAt,
            deviceID: deviceID,
            crashInjection: crashInjection,
            insertBusinessRow: insertBusinessRow
        )
    }

    /// 既存Identifierを同じtransactionで再検査し、MaterializationとReceipt duplicateを同時確定します。
    /// - Parameters:
    ///   - materializationID: `linked_existing_duplicate`の予約済みMaterialization ID。
    ///   - receiptID: 同じLogical Changeのvalidated Receipt ID。
    ///   - appliedAt: 永続適用時刻。
    ///   - deviceID: 適用端末ID。
    ///   - crashInjection: rollback試験専用Crash point。
    /// - Throws: ID、Vehicle、kind、Digest Version、Lookup Digest、canonical digestの不一致。
    func applyLinkedIdentifierDuplicate(
        materializationID: UUID,
        receiptID: UUID,
        appliedAt: Date,
        deviceID: UUID,
        crashInjection: CrashInjectionPoint = .none
    ) throws {
        try applyAtomically(
            materializationID: materializationID,
            receiptID: receiptID,
            terminalReceiptState: "duplicate",
            appliedAt: appliedAt,
            deviceID: deviceID,
            crashInjection: crashInjection,
            insertBusinessRow: nil
        )
    }

    /// projected集合が固定されたpreparing graphへcanonical manifestを一度封印します。
    /// - Parameters:
    ///   - aliasID: preparing Alias ID。
    ///   - updatedAt: 封印時刻。
    ///   - deviceID: 更新端末ID。
    /// - Throws: applied行を含むgraph、未知Alias、SQL制約のエラー。
    func sealAliasGraphManifest(aliasID: UUID, updatedAt: Date, deviceID: UUID) throws {
        do { try databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) {
            guard let alias=try Row.fetchOne(database,sql:"SELECT alias_revision,graph_source_frontier FROM vehicle_id_aliases WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state='preparing'",arguments:[scopeString,uuid(aliasID)]),
                  try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM origin_entity_materializations WHERE user_scope_id=? AND vehicle_alias_id=? AND graph_generation=? AND materialization_state<>'projected'",arguments:[scopeString,uuid(aliasID),alias["alias_revision"] as Int]) == 0 else { throw SyncPersistenceError.blocked }
            let digest=try MaterializedEntityDigestV1.graphManifestDigest(database:database,scope:scopeString,aliasID:uuid(aliasID),generation:alias["alias_revision"],sourceFrontier:alias["graph_source_frontier"])
            try database.execute(sql:"UPDATE vehicle_id_aliases SET graph_manifest_digest=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state='preparing'",arguments:[digest,timestamp(updatedAt),uuid(deviceID),scopeString,uuid(aliasID)])
            guard database.changesCount == 1 else { throw SyncPersistenceError.conflict }
            return .commit
        }}} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable }
    }

    /// 件数、frontier、全Digest、親子関係、Identifier結果、Chunk目録、manifestを再検査してready化します。
    func markAliasReady(aliasID: UUID, readyAt: Date, deviceID: UUID) throws {
        do { try databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) {
            _ = try verifyAliasGraph(database: database, aliasID: uuid(aliasID), requiredState: "preparing")
            try database.execute(sql:"UPDATE vehicle_id_aliases SET mapping_state='ready',ready_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state='preparing'",arguments:[timestamp(readyAt),timestamp(readyAt),uuid(deviceID),scopeString,uuid(aliasID)])
            guard database.changesCount == 1 else { throw SyncPersistenceError.conflict }
            return .commit
        }}} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable }
    }

    /// active部分Unique Indexが常に一件になる順序で旧新graphを切り替えます。
    func publishAlias(aliasID: UUID, activatedAt: Date, deviceID: UUID) throws {
        try publishAlias(aliasID: aliasID, activatedAt: activatedAt, deviceID: deviceID, crashInjection: .none)
    }

    /// Alias公開切替をCrash injection可能な一つの即時transactionで実行します。
    /// - Parameters:
    ///   - aliasID: 公開するready Alias。
    ///   - activatedAt: 公開時刻。
    ///   - deviceID: 更新端末ID。
    ///   - crashInjection: rollback試験専用Crash point。
    /// - Throws: graph再検査または旧active整合性に失敗した場合の安定エラー。
    func publishAlias(aliasID: UUID, activatedAt: Date, deviceID: UUID, crashInjection: CrashInjectionPoint) throws {
        do { try databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) {
            let next = try verifyAliasGraph(database: database, aliasID: uuid(aliasID), requiredState: "ready")
            let previous: String?=next["previous_alias_id"]
            if let previous {
                let old = try verifyAliasGraph(database: database, aliasID: previous, requiredState: "active")
                guard (old["source_peer_identity_id"] as String) == (next["source_peer_identity_id"] as String),
                      (old["source_vehicle_id"] as String) == (next["source_vehicle_id"] as String) else { throw SyncPersistenceError.blocked }
                try database.execute(sql:"UPDATE vehicle_id_aliases SET mapping_state='superseded',superseded_by_alias_id=?,superseded_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state='active'",arguments:[uuid(aliasID),timestamp(activatedAt),timestamp(activatedAt),uuid(deviceID),scopeString,previous])
                if crashInjection == .afterOldAliasSuperseded { throw SyncPersistenceError.unavailable }
            } else {
                guard try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM vehicle_id_aliases WHERE user_scope_id=? AND source_peer_identity_id=? AND source_vehicle_id=? AND mapping_state='active'",arguments:[scopeString,next["source_peer_identity_id"] as String,next["source_vehicle_id"] as String])==0 else { throw SyncPersistenceError.blocked }
            }
            try database.execute(sql:"UPDATE vehicle_id_aliases SET mapping_state='active',activated_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state='ready'",arguments:[timestamp(activatedAt),timestamp(activatedAt),uuid(deviceID),scopeString,uuid(aliasID)])
            guard database.changesCount==1 else { throw SyncPersistenceError.conflict }
            return .commit
        }}} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable }
    }

    /// 全業務目録と親子関係を再計算し、Durable ACK保存を同じtransactionで行います。
    func markSessionTransferDurable(transferID: UUID, acknowledgementID: UUID, durableAt: Date, deviceID: UUID) throws { do { try databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) {
        guard let transfer = try Row.fetchOne(database, sql:"SELECT s.*,b.peer_identity_id,b.batch_state,b.transfer_id AS batch_transfer_id FROM session_transfers s JOIN sync_batches b ON b.user_scope_id=s.user_scope_id AND b.batch_id=s.batch_id WHERE s.user_scope_id=? AND s.session_transfer_id=?", arguments:[scopeString,uuid(transferID)]) else { throw SyncPersistenceError.blocked }
        let state: String = transfer["transfer_state"]
        guard state == "verifying" || state == "durable" || state == "acknowledged" else { throw SyncPersistenceError.blocked }
        if state == "verifying" {
            guard (transfer["batch_state"] as String) == "applying" || (transfer["batch_state"] as String) == "waiting_ack" else { throw SyncPersistenceError.blocked }
        } else {
            guard (transfer["durable_ack_id"] as String) == uuid(acknowledgementID) else { throw SyncPersistenceError.conflict }
        }
        let expectedCount: Int = transfer["expected_chunk_count"], expectedBytes: Int64 = transfer["expected_ciphertext_bytes"]
        let chunks = try Row.fetchAll(database, sql:"""
            SELECT c.*
            FROM chunk_transfers c
            JOIN active_or_local_log_chunks l
              ON l.user_scope_id=c.user_scope_id AND l.session_id=c.session_id AND l.chunk_id=c.chunk_id
             AND l.stream_id=c.stream_id AND l.chunk_sequence=c.chunk_sequence
             AND l.clock_epoch_id=c.clock_epoch_id AND l.first_record_sequence=c.first_record_sequence
             AND l.last_record_sequence=c.last_record_sequence AND l.first_monotonic_ns=c.first_monotonic_ns
             AND l.last_monotonic_ns=c.last_monotonic_ns AND l.record_count=c.record_count
             AND l.plaintext_size=c.plaintext_size AND l.compressed_size=c.compressed_size
             AND l.ciphertext_size=c.ciphertext_size AND l.ciphertext_digest=c.ciphertext_digest
             AND l.catalog_digest=c.catalog_digest AND l.record_format_version=c.record_format_version
             AND l.compression_format_version=c.compression_format_version
             AND l.encryption_format_version=c.encryption_format_version AND l.key_version=c.key_version
             AND l.relative_path=c.catalog_relative_path AND l.storage_state=c.catalog_storage_state
             AND l.revision=c.catalog_revision AND l.created_at_utc=c.catalog_created_at_utc
             AND l.updated_at_utc=c.catalog_updated_at_utc
            WHERE c.user_scope_id=? AND c.session_transfer_id=? AND c.session_id=? AND c.transfer_state='cataloged'
            ORDER BY c.stream_id,c.chunk_sequence,c.chunk_id
            """, arguments:[scopeString,uuid(transferID),transfer["session_id"] as String])
        let canonicalManifest = try MaterializedEntityDigestV1.sessionManifestDigest(database:database,scope:scopeString,sessionID:transfer["session_id"])
        guard chunks.count == expectedCount,
              chunks.reduce(Int64(0), { $0 + ($1["ciphertext_size"] as Int64) }) == expectedBytes,
              canonicalManifest == (transfer["manifest_digest"] as Data),
              try chunks.allSatisfy({ row in
                  try Int.fetchOne(database, sql:"SELECT COUNT(*) FROM wrapped_key_receipts WHERE user_scope_id=? AND sender_identity_id=? AND key_purpose='session_chunk' AND wrapped_key_version=? AND bound_session_id=? AND bound_chunk_id=? AND receipt_state='applied' AND transition_step>=2", arguments:[scopeString,transfer["peer_identity_id"] as String,row["key_version"] as Int,transfer["session_id"] as String,row["chunk_id"] as String]) == 1
              }) else { throw SyncPersistenceError.blocked }
        let binding = MaterializedEntityDigestV1.acknowledgementBindingDigest(peerID:transfer["peer_identity_id"],batchID:transfer["batch_id"],batchTransferID:transfer["batch_transfer_id"],sessionTransferID:uuid(transferID),sessionID:transfer["session_id"],manifestDigest:transfer["manifest_digest"],acknowledgementID:uuid(acknowledgementID))
        if state == "durable" || state == "acknowledged" {
            guard (transfer["durable_ack_binding_digest"] as Data) == binding else { throw SyncPersistenceError.blocked }
            return .commit
        }
        try database.execute(sql:"UPDATE session_transfers SET transfer_state='durable',transition_step=transition_step+1,durable_ack_id=?,durable_ack_binding_digest=?,durable_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND session_transfer_id=? AND transfer_state='verifying'",arguments:[uuid(acknowledgementID),binding,timestamp(durableAt),timestamp(durableAt),uuid(deviceID),scopeString,uuid(transferID)])
        guard database.changesCount==1 else { throw SyncPersistenceError.conflict }
        return .commit
    }}} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable } }

    /// Materialization結果別のatomic適用本体です。
    /// - Parameters:
    ///   - materializationID: 予約済みMaterialization ID。
    ///   - receiptID: validated Receipt ID。
    ///   - terminalReceiptState: appliedまたはduplicate。
    ///   - appliedAt: 適用時刻。
    ///   - deviceID: 適用端末ID。
    ///   - crashInjection: rollback試験専用Crash point。
    ///   - insertBusinessRow: inserted時だけ実行する業務行INSERT。
    /// - Throws: 再読戻し検査またはtransaction更新失敗。
    private func applyAtomically(materializationID: UUID, receiptID: UUID, terminalReceiptState: String, appliedAt: Date, deviceID: UUID, crashInjection: CrashInjectionPoint, insertBusinessRow: ((Database) throws -> Void)?) throws {
        do { try databasePool.writeWithoutTransaction { database in try database.inTransaction(.immediate) {
            // raw table access: 未公開Projectionを確定するtransaction内整合性検査専用です。
            guard let materialization = try Row.fetchOne(database, sql:"SELECT * FROM origin_entity_materializations WHERE user_scope_id=? AND materialization_id=? AND materialization_state='projected'", arguments:[scopeString,uuid(materializationID)]),
                  let receipt = try Row.fetchOne(database, sql:"SELECT logical_change_id,apply_state,revision FROM received_changes WHERE user_scope_id=? AND receipt_id=?", arguments:[scopeString,uuid(receiptID)]),
                  (receipt["logical_change_id"] as String) == (materialization["logical_change_id"] as String),
                  (receipt["apply_state"] as String) == "validated" else { throw SyncPersistenceError.blocked }
            let resultKind: String = materialization["materialization_result_kind"]
            guard (resultKind == "inserted_projection" && terminalReceiptState == "applied" && insertBusinessRow != nil)
                    || (resultKind == "linked_existing_duplicate" && terminalReceiptState == "duplicate" && insertBusinessRow == nil) else { throw SyncPersistenceError.invalidRequest }
            try insertBusinessRow?(database)
            if crashInjection == .afterBusinessInsert { throw SyncPersistenceError.unavailable }
            let entityKind: String = materialization["entity_kind"], entityID: String = materialization["materialized_entity_id"]
            guard let digest = try MaterializedEntityDigestV1.digest(database:database,scope:scopeString,entityKind:entityKind,entityID:entityID), digest == (materialization["materialized_content_digest"] as Data) else { throw SyncPersistenceError.blocked }
            if resultKind == "linked_existing_duplicate" {
                // raw table access: linked duplicate適用transaction内の既存Identifier再検査専用です。
                guard entityKind == "vehicle_identifier",
                      let identifier = try Row.fetchOne(database,sql:"SELECT vehicle_id,identifier_kind,digest_key_version,lookup_digest FROM vehicle_identifiers WHERE user_scope_id=? AND identifier_id=?",arguments:[scopeString,entityID]),
                      (identifier["vehicle_id"] as String) == (materialization["canonical_vehicle_id"] as String),
                      (identifier["identifier_kind"] as String) == (materialization["materialized_identifier_kind"] as String),
                      (identifier["digest_key_version"] as Int) == (materialization["materialized_identifier_digest_key_version"] as Int),
                      (identifier["lookup_digest"] as Data) == (materialization["materialized_identifier_lookup_digest"] as Data),
                      // raw table access: linked duplicate候補の一意性を同じtransactionで再検査します。
                      try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM vehicle_identifiers WHERE user_scope_id=? AND identifier_kind=? AND digest_key_version=? AND lookup_digest=?",arguments:[scopeString,identifier["identifier_kind"] as String,identifier["digest_key_version"] as Int,identifier["lookup_digest"] as Data]) == 1 else { throw SyncPersistenceError.blocked }
            }
            let stamp=timestamp(appliedAt), device=uuid(deviceID)
            try database.execute(sql:"UPDATE origin_entity_materializations SET materialization_state='applied',applied_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND materialization_id=? AND materialization_state='projected'",arguments:[stamp,stamp,device,scopeString,uuid(materializationID)])
            guard database.changesCount == 1 else { throw SyncPersistenceError.conflict }
            if crashInjection == .afterMaterializationApplied { throw SyncPersistenceError.unavailable }
            try database.execute(sql:"UPDATE received_changes SET apply_state=?,applied_revision=?,applied_at=?,updated_at=?,updated_by_device_id=?,revision=revision+1 WHERE user_scope_id=? AND receipt_id=? AND apply_state='validated'",arguments:[terminalReceiptState,(receipt["revision"] as Int)+1,stamp,stamp,device,scopeString,uuid(receiptID)])
            guard database.changesCount == 1 else { throw SyncPersistenceError.conflict }
            return .commit
        }}} catch let error as SyncPersistenceError { throw error } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw SyncPersistenceError.blocked } catch { throw SyncPersistenceError.unavailable }
    }

    /// Alias graphの全readiness条件と保存Manifestを再検査します。
    /// - Parameters:
    ///   - database: 同一即時transactionの接続。
    ///   - aliasID: Alias ID。
    ///   - requiredState: preparing、ready、activeのいずれか。
    /// - Returns: 検査済みAlias行。
    /// - Throws: 不完全graphまたはManifest不一致。
    private func verifyAliasGraph(database: Database, aliasID: String, requiredState: String) throws -> Row {
        guard let alias=try Row.fetchOne(database,sql:"SELECT * FROM vehicle_id_aliases WHERE user_scope_id=? AND vehicle_alias_id=? AND mapping_state=?",arguments:[scopeString,aliasID,requiredState]) else { throw SyncPersistenceError.conflict }
        let generation: Int=alias["alias_revision"], frontier: Data=alias["graph_source_frontier"], expectedCount: Int=alias["expected_materialization_count"]
        guard !frontier.isEmpty, frontier.first == 1 else { throw SyncPersistenceError.blocked }
        // raw table access: Alias readiness/publicationのtransaction内整合性検査専用です。
        let invalid = try Int.fetchOne(database,sql:"""
            SELECT COUNT(*) FROM origin_entity_materializations m
            WHERE m.user_scope_id=? AND m.vehicle_alias_id=? AND m.graph_generation=? AND (
              m.materialization_state<>'applied' OR m.canonical_vehicle_id<>? OR
              NOT EXISTS(SELECT 1 FROM logical_sync_changes c WHERE c.user_scope_id=m.user_scope_id AND c.logical_change_id=m.logical_change_id AND c.origin_device_identity_id=m.origin_device_identity_id AND c.origin_change_id=m.origin_change_id AND c.entity_kind=m.entity_kind AND c.entity_id=m.origin_entity_id AND c.origin_vehicle_id=m.origin_vehicle_id AND c.origin_parent_entity_kind=m.origin_parent_entity_kind AND c.origin_parent_entity_id=m.origin_parent_entity_id AND c.origin_secondary_parent_entity_kind IS m.origin_secondary_parent_entity_kind AND c.origin_secondary_parent_entity_id IS m.origin_secondary_parent_entity_id AND c.origin_tertiary_parent_entity_kind IS m.origin_tertiary_parent_entity_kind AND c.origin_tertiary_parent_entity_id IS m.origin_tertiary_parent_entity_id AND c.entity_schema_version=m.origin_entity_version AND c.content_digest=m.origin_content_digest) OR
              (m.parent_materialization_id IS NULL AND NOT(m.origin_parent_entity_kind='vehicle' AND m.origin_parent_entity_id=? AND m.materialized_parent_entity_id=?)) OR
              (m.parent_materialization_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM origin_entity_materializations p WHERE p.user_scope_id=m.user_scope_id AND p.materialization_id=m.parent_materialization_id AND p.materialization_state='applied' AND p.entity_kind=m.origin_parent_entity_kind AND p.origin_entity_id=m.origin_parent_entity_id AND p.materialized_entity_id=m.materialized_parent_entity_id AND p.vehicle_alias_id=m.vehicle_alias_id AND p.graph_generation=m.graph_generation AND p.canonical_vehicle_id=m.canonical_vehicle_id AND p.origin_device_identity_id=m.origin_device_identity_id AND p.origin_vehicle_id=m.origin_vehicle_id)) OR
              (m.secondary_parent_materialization_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM origin_entity_materializations p WHERE p.user_scope_id=m.user_scope_id AND p.materialization_id=m.secondary_parent_materialization_id AND p.materialization_state='applied' AND p.entity_kind=m.origin_secondary_parent_entity_kind AND p.origin_entity_id=m.origin_secondary_parent_entity_id AND p.materialized_entity_id=m.materialized_secondary_parent_entity_id AND p.vehicle_alias_id=m.vehicle_alias_id AND p.graph_generation=m.graph_generation AND p.canonical_vehicle_id=m.canonical_vehicle_id AND p.origin_device_identity_id=m.origin_device_identity_id AND p.origin_vehicle_id=m.origin_vehicle_id)) OR
              (m.tertiary_parent_materialization_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM origin_entity_materializations p WHERE p.user_scope_id=m.user_scope_id AND p.materialization_id=m.tertiary_parent_materialization_id AND p.materialization_state='applied' AND p.entity_kind=m.origin_tertiary_parent_entity_kind AND p.origin_entity_id=m.origin_tertiary_parent_entity_id AND p.materialized_entity_id=m.materialized_tertiary_parent_entity_id AND p.vehicle_alias_id=m.vehicle_alias_id AND p.graph_generation=m.graph_generation AND p.canonical_vehicle_id=m.canonical_vehicle_id AND p.origin_device_identity_id=m.origin_device_identity_id AND p.origin_vehicle_id=m.origin_vehicle_id)))
            """,arguments:[scopeString,aliasID,generation,alias["canonical_vehicle_id"] as String,alias["source_vehicle_id"] as String,alias["canonical_vehicle_id"] as String])
        let count = try Int.fetchOne(database,sql:"SELECT COUNT(*) FROM origin_entity_materializations WHERE user_scope_id=? AND vehicle_alias_id=? AND graph_generation=?",arguments:[scopeString,aliasID,generation])
        guard count == expectedCount, invalid == 0 else { throw SyncPersistenceError.blocked }
        let manifest=try MaterializedEntityDigestV1.graphManifestDigest(database:database,scope:scopeString,aliasID:aliasID,generation:generation,sourceFrontier:frontier)
        guard manifest == (alias["graph_manifest_digest"] as Data) else { throw SyncPersistenceError.blocked }
        return alias
    }

    /// UUIDをDB canonical文字列へ変換します。
    private func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    /// Dateを固定UTC文字列へ変換します。
    private func timestamp(_ value: Date) -> String { GRDBVehicleDateCodec.string(from:value) }
}
