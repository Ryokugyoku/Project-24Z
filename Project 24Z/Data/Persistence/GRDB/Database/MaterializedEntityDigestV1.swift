import CryptoKit
import Foundation
import GRDB

/// 同期Projectionの業務行をVersion固定のcanonical bytesへ変換してSHA-256を計算します。
enum MaterializedEntityDigestV1 {
    /// Session Manifestへ含める一つのChunk目録値です。
    struct ChunkManifestComponent {
        /// Chunk IDです。
        let chunkID: String
        /// Stream IDです。
        let streamID: String
        /// Stream内Sequenceです。
        let sequence: Int64
        /// 暗号文bytes数です。
        let ciphertextSize: Int64
        /// 暗号文SHA-256です。
        let ciphertextDigest: Data
        /// Record format versionです。
        let recordFormatVersion: Int
        /// Compression format versionです。
        let compressionFormatVersion: Int
        /// Encryption format versionです。
        let encryptionFormatVersion: Int
        /// Chunk key versionです。
        let keyVersion: Int
        /// Catalog row全体のcanonical SHA-256です。
        let catalogDigest: Data
    }

    /// transaction内の業務行をraw tableから読戻し、保存済みexpected digestとの照合値を返します。
    ///
    /// このraw table参照は通常Repository Queryではなく、未公開Projectionを含むatomic整合性検査専用です。
    /// - Parameters:
    ///   - database: Materializationを確定する同一write transactionの接続。
    ///   - scope: DBへ固定されたユーザースコープ。
    ///   - entityKind: 設計で許可された9種類のEntity種別。
    ///   - entityID: 読戻すMaterialized Entity ID。
    /// - Returns: Version 1 canonical SHA-256。対象がなければ`nil`。
    /// - Throws: SQL読取または未対応Entity種別のエラー。
    static func digest(
        database: Database,
        scope: String,
        entityKind: String,
        entityID: String
    ) throws -> Data? {
        guard let descriptor = descriptor(for: entityKind) else {
            throw SyncPersistenceError.invalidRequest
        }
        let sql = "SELECT \(descriptor.columns.joined(separator: ",")) FROM \(descriptor.table) WHERE user_scope_id=? AND \(descriptor.idColumn)=?"
        guard let row = try Row.fetchOne(database, sql: sql, arguments: [scope, entityID]) else {
            return nil
        }
        var bytes = Data("project24z-materialized-entity-v1".utf8)
        append(Data(entityKind.utf8), to: &bytes)
        for column in descriptor.columns {
            append(databaseValue: row[column], to: &bytes)
        }
        return Data(SHA256.hash(data: bytes))
    }

    /// Alias graphのfrontier、全expected digest、親子関係、Identifier結果、Chunk目録を束縛します。
    /// - Parameters:
    ///   - database: Alias readinessを検査する同一write transactionの接続。
    ///   - scope: ユーザースコープ。
    ///   - aliasID: 対象Alias ID。
    ///   - generation: 対象graph generation。
    ///   - sourceFrontier: Version付きsource frontier bytes。
    /// - Returns: 順序固定のgraph manifest SHA-256。
    /// - Throws: SQL読取エラー。
    static func graphManifestDigest(
        database: Database,
        scope: String,
        aliasID: String,
        generation: Int,
        sourceFrontier: Data
    ) throws -> Data {
        // raw table access: preparing graphを検査するreadiness専用で、通常公開Queryではありません。
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT materialization_id,logical_change_id,entity_kind,origin_entity_id,
                   origin_parent_entity_kind,origin_parent_entity_id,
                   origin_secondary_parent_entity_kind,origin_secondary_parent_entity_id,
                   origin_tertiary_parent_entity_kind,origin_tertiary_parent_entity_id,
                   parent_materialization_id,materialized_parent_entity_id,
                   secondary_parent_materialization_id,materialized_secondary_parent_entity_id,
                   tertiary_parent_materialization_id,materialized_tertiary_parent_entity_id,
                   projection_version,canonical_vehicle_id,materialization_result_kind,
                   materialized_identifier_kind,materialized_identifier_digest_key_version,
                   materialized_identifier_lookup_digest,materialized_content_digest,
                   materialized_entity_id
            FROM origin_entity_materializations
            WHERE user_scope_id=? AND vehicle_alias_id=? AND graph_generation=?
            ORDER BY materialization_id
            """,
            arguments: [scope, aliasID, generation]
        )
        var bytes = Data("project24z-alias-graph-manifest-v1".utf8)
        append(sourceFrontier, to: &bytes)
        appendInteger(Int64(rows.count), to: &bytes)
        for row in rows {
            for column in row.columnNames {
                append(databaseValue: row[column], to: &bytes)
            }
        }
        return Data(SHA256.hash(data: bytes))
    }

    /// ACK IDをPeer、Batch、Transfer、Session、Manifestへ決定的に束縛します。
    /// - Parameters:
    ///   - peerID: 受信元Peer ID。
    ///   - batchID: Batch ID。
    ///   - batchTransferID: Batchが属するwire Transfer ID。
    ///   - sessionTransferID: Session Transfer ID。
    ///   - sessionID: Session ID。
    ///   - manifestDigest: 期待Manifest digest。
    ///   - acknowledgementID: 永続ACK ID。
    /// - Returns: ACK binding SHA-256。
    static func acknowledgementBindingDigest(
        peerID: String,
        batchID: String,
        batchTransferID: String,
        sessionTransferID: String,
        sessionID: String,
        manifestDigest: Data,
        acknowledgementID: String
    ) -> Data {
        var bytes = Data("project24z-durable-ack-binding-v1".utf8)
        [peerID, batchID, batchTransferID, sessionTransferID, sessionID, acknowledgementID].forEach { append(Data($0.utf8), to: &bytes) }
        append(manifestDigest, to: &bytes)
        return Data(SHA256.hash(data: bytes))
    }

    /// active-or-local業務目録から親子順のcanonical Session Manifestを再計算します。
    ///
    /// Session、Stream、Clock Epoch、Gap、Chunkを順に含め、各行のVersion／Revisionを含む
    /// 全canonical列と親IDを束縛します。未公開Projectionや壊れた親子関係はView／JOINから除外され、
    /// 元tableとの件数差を検出して`blocked`にします。
    /// - Parameters:
    ///   - database: ACKを確定する同一write transactionの接続。
    ///   - scope: DBへ固定されたユーザースコープ。
    ///   - sessionID: 対象Session ID。
    /// - Returns: Version 2 Session Manifest SHA-256。
    /// - Throws: Entity欠落、非公開Materialization、親子不一致、SQL読取エラー。
    static func sessionManifestDigest(
        database: Database,
        scope: String,
        sessionID: String
    ) throws -> Data {
        let specifications: [(kind: String, view: String, table: String, predicate: String, order: String)] = [
            ("acquisition_session", "active_or_local_acquisition_sessions", "acquisition_sessions", "session_id=?", "session_id"),
            ("acquisition_stream", "active_or_local_acquisition_streams", "acquisition_streams", "session_id=?", "stream_id"),
            ("clock_epoch", "active_or_local_clock_epochs", "clock_epochs", "session_id=?", "clock_epoch_id"),
            ("acquisition_gap", "active_or_local_acquisition_gaps", "acquisition_gaps", "session_id=?", "stream_id,gap_id"),
            ("log_chunk_manifest", "active_or_local_log_chunks", "log_chunks", "session_id=?", "stream_id,chunk_sequence,chunk_id"),
        ]
        var bytes = Data("project24z-session-manifest-v2".utf8)
        append(Data(sessionID.utf8), to: &bytes)
        for specification in specifications {
            let visible = try Row.fetchAll(
                database,
                sql: "SELECT * FROM \(specification.view) WHERE user_scope_id=? AND \(specification.predicate) ORDER BY \(specification.order)",
                arguments: [scope, sessionID]
            )
            let storedCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \(specification.table) WHERE user_scope_id=? AND \(specification.predicate)",
                arguments: [scope, sessionID]
            ) ?? 0
            guard visible.count == storedCount, specification.kind != "acquisition_session" || visible.count == 1 else {
                throw SyncPersistenceError.blocked
            }
            append(Data(specification.kind.utf8), to: &bytes)
            appendInteger(Int64(visible.count), to: &bytes)
            for row in visible {
                for column in row.columnNames {
                    append(databaseValue: row[column], to: &bytes)
                }
            }
        }
        let invalidRelations = try Int.fetchOne(
            database,
            sql: """
            SELECT
              (SELECT COUNT(*) FROM active_or_local_acquisition_streams s WHERE s.user_scope_id=? AND s.session_id=? AND NOT EXISTS(
                SELECT 1 FROM active_or_local_acquisition_sessions p WHERE p.user_scope_id=s.user_scope_id AND p.session_id=s.session_id)) +
              (SELECT COUNT(*) FROM active_or_local_clock_epochs e WHERE e.user_scope_id=? AND e.session_id=? AND NOT EXISTS(
                SELECT 1 FROM active_or_local_acquisition_sessions p WHERE p.user_scope_id=e.user_scope_id AND p.session_id=e.session_id)) +
              (SELECT COUNT(*) FROM active_or_local_acquisition_gaps g WHERE g.user_scope_id=? AND g.session_id=? AND (
                NOT EXISTS(SELECT 1 FROM active_or_local_acquisition_streams s WHERE s.user_scope_id=g.user_scope_id AND s.session_id=g.session_id AND s.stream_id=g.stream_id) OR
                NOT EXISTS(SELECT 1 FROM active_or_local_clock_epochs e WHERE e.user_scope_id=g.user_scope_id AND e.session_id=g.session_id AND e.clock_epoch_id=g.start_clock_epoch_id) OR
                (g.end_clock_epoch_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM active_or_local_clock_epochs e WHERE e.user_scope_id=g.user_scope_id AND e.session_id=g.session_id AND e.clock_epoch_id=g.end_clock_epoch_id)))) +
              (SELECT COUNT(*) FROM active_or_local_log_chunks c WHERE c.user_scope_id=? AND c.session_id=? AND (c.storage_state<>'available' OR
                NOT EXISTS(SELECT 1 FROM active_or_local_acquisition_streams s WHERE s.user_scope_id=c.user_scope_id AND s.session_id=c.session_id AND s.stream_id=c.stream_id) OR
                NOT EXISTS(SELECT 1 FROM active_or_local_clock_epochs e WHERE e.user_scope_id=c.user_scope_id AND e.session_id=c.session_id AND e.clock_epoch_id=c.clock_epoch_id)))
            """,
            arguments: [scope, sessionID, scope, sessionID, scope, sessionID, scope, sessionID]
        ) ?? 0
        guard invalidRelations == 0 else { throw SyncPersistenceError.blocked }
        return Data(SHA256.hash(data: bytes))
    }

    /// Sessionと全Chunkの件数、bytes、Digest、4 Version、Catalog Digestを束縛します。
    /// - Parameters:
    ///   - sessionID: Session ID。
    ///   - chunks: `(streamID, sequence)`順の完全なChunk集合。
    /// - Returns: Version 1 Session Manifest SHA-256。
    static func sessionManifestDigest(sessionID: String, chunks: [ChunkManifestComponent]) -> Data {
        var bytes = Data("project24z-session-chunk-manifest-v2".utf8)
        append(Data(sessionID.utf8), to: &bytes)
        appendInteger(Int64(chunks.count), to: &bytes)
        appendInteger(chunks.reduce(0) { $0 + $1.ciphertextSize }, to: &bytes)
        for chunk in chunks {
            append(Data(chunk.chunkID.utf8), to: &bytes)
            append(Data(chunk.streamID.utf8), to: &bytes)
            appendInteger(chunk.sequence, to: &bytes)
            appendInteger(chunk.ciphertextSize, to: &bytes)
            append(chunk.ciphertextDigest, to: &bytes)
            appendInteger(Int64(chunk.recordFormatVersion), to: &bytes)
            appendInteger(Int64(chunk.compressionFormatVersion), to: &bytes)
            appendInteger(Int64(chunk.encryptionFormatVersion), to: &bytes)
            appendInteger(Int64(chunk.keyVersion), to: &bytes)
            append(chunk.catalogDigest, to: &bytes)
        }
        return Data(SHA256.hash(data: bytes))
    }

    /// Entity種別を物理tableとcanonical列へ対応付けます。
    /// - Parameter entityKind: 同期Entity種別。
    /// - Returns: 対応表。未対応なら`nil`。
    private static func descriptor(for entityKind: String) -> (table: String, idColumn: String, columns: [String])? {
        switch entityKind {
        case "vehicle_identification_scan":
            ("vehicle_identification_scans", "scan_id", ["user_scope_id","scan_id","vehicle_id","obd_connection_id","transport_kind","diagnostic_protocol_kind","adapter_reference_id","decoder_version","normalization_version","scan_status","decode_state","identity_validation_state","termination_reason_code","started_at","finished_at","revision","created_at","created_by_device_id","updated_at","updated_by_device_id"])
        case "vehicle_identifier":
            ("vehicle_identifiers", "identifier_id", ["user_scope_id","identifier_id","vehicle_id","identifier_kind","normalized_value_ciphertext","encryption_key_version","lookup_digest","digest_key_version","source_scan_id","revision","created_at","created_by_device_id","updated_at","updated_by_device_id"])
        case "ecu_observation":
            ("ecu_observations", "ecu_observation_id", ["user_scope_id","ecu_observation_id","scan_id","observation_ordinal","responder_address_format","responder_address","revision","created_at","created_by_device_id","updated_at","updated_by_device_id"])
        case "ecu_identification_value":
            ("ecu_identification_values", "identification_value_id", ["user_scope_id","identification_value_id","ecu_observation_id","info_type_code","occurrence_ordinal","value_kind","decode_state","validation_state","decoded_value_ciphertext","decoded_value_key_version","raw_response_ciphertext","raw_response_key_version","revision","created_at","created_by_device_id","updated_at","updated_by_device_id"])
        case "acquisition_session":
            ("acquisition_sessions", "session_id", ["user_scope_id","session_id","vehicle_id","vehicle_binding_state","capture_state","disposition_state","integrity_state","end_reason_code","started_at_utc","ended_at_utc","reviewed_at_utc","disposition_requested_at_utc","disposition_completed_at_utc","created_by_device_id","record_revision","updated_at_utc","updated_by_device_id"])
        case "acquisition_stream":
            ("acquisition_streams", "stream_id", ["user_scope_id","stream_id","session_id","stream_kind","adapter_role","adapter_reference_id","connection_instance_id","stream_state","started_at_utc","ended_at_utc","next_record_sequence","next_chunk_sequence","record_revision","updated_at_utc"])
        case "clock_epoch":
            ("clock_epochs", "clock_epoch_id", ["user_scope_id","clock_epoch_id","session_id","process_instance_id","device_id","monotonic_clock_kind","wall_clock_anchor_utc","anchor_uncertainty_ns","started_at_utc","ended_at_utc","revision"])
        case "acquisition_gap":
            ("acquisition_gaps", "gap_id", ["user_scope_id","gap_id","session_id","stream_id","reason_code","detection_method","start_boundary_certainty","start_clock_epoch_id","start_monotonic_ns","start_utc","end_clock_epoch_id","end_monotonic_ns","end_utc","end_boundary_certainty","first_missing_sequence","missing_record_count","revision","created_at_utc"])
        case "log_chunk_manifest":
            ("log_chunks", "chunk_id", ["user_scope_id","chunk_id","session_id","stream_id","chunk_sequence","clock_epoch_id","first_record_sequence","last_record_sequence","first_monotonic_ns","last_monotonic_ns","record_count","plaintext_size","compressed_size","ciphertext_size","record_format_version","compression_format_version","encryption_format_version","key_version","ciphertext_digest","catalog_digest","relative_path","storage_state","revision","created_at_utc","updated_at_utc"])
        default:
            nil
        }
    }

    /// SQLite値を型tag付きcanonical bytesへ追記します。
    /// - Parameters:
    ///   - databaseValue: GRDBが返した値。
    ///   - bytes: 追記先。
    private static func append(databaseValue: DatabaseValue, to bytes: inout Data) {
        switch databaseValue.storage {
        case .null:
            bytes.append(0)
        case .int64(let value):
            bytes.append(1); appendInteger(value, to: &bytes)
        case .double(let value):
            bytes.append(2); appendInteger(Int64(bitPattern: value.bitPattern), to: &bytes)
        case .string(let value):
            bytes.append(3); append(Data(value.utf8), to: &bytes)
        case .blob(let value):
            bytes.append(4); append(value, to: &bytes)
        }
    }

    /// 長さ付きbytesを追記します。
    /// - Parameters:
    ///   - value: 追記するbytes。
    ///   - bytes: 追記先。
    private static func append(_ value: Data, to bytes: inout Data) {
        appendInteger(Int64(value.count), to: &bytes)
        bytes.append(value)
    }

    /// signed 64-bit整数をbig-endianで追記します。
    /// - Parameters:
    ///   - value: 追記する整数。
    ///   - bytes: 追記先。
    private static func appendInteger(_ value: Int64, to bytes: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }
}
