import Foundation
import GRDB

/// scope専用GRDBへAcquisition目録をtransaction保存します。
final class GRDBAcquisitionRepository: AcquisitionRepository, SessionVehicleBindingRepository, UnassignedSessionRepository {
    private let databasePool: DatabasePool
    private let scopeString: String
    private let catalogDigester = SHA256AcquisitionChunkCatalogDigester()

    /// 検査済みDatabasePoolとscopeを受け取ります。
    /// - Parameters:
    ///   - databasePool: Migrationと起動時保全検査済みPool。
    ///   - userScopeID: Poolの唯一のscope。
    init(databasePool: DatabasePool, userScopeID: UUID) {
        self.databasePool = databasePool
        scopeString = userScopeID.uuidString.lowercased()
    }

    /// Session、異種Stream、Clock Epochを一transactionで作ります。
    /// - Parameters:
    ///   - session: 未割当または登録済みの新規Session。
    ///   - streams: PID、Raw CAN、または両方。空は拒否します。
    ///   - epoch: 最初のprocess clock epoch。
    /// - Throws: 制約競合や入力不正時の安定エラー。
    func start(session: AcquisitionSession, streams: [AcquisitionStream], epoch: AcquisitionClockEpoch) throws {
        guard session.captureState == .recording,
              session.dispositionState == .pendingDecision,
              session.integrityState == .unchecked,
              session.revision == 1,
              session.endedAt == nil,
              !streams.isEmpty,
              Set(streams.map(\.kind)).count == streams.count,
              streams.allSatisfy({ $0.sessionID == session.sessionID && $0.state == .active && $0.revision == 1 }),
              epoch.sessionID == session.sessionID else {
            throw AcquisitionPersistenceError.invalidRequest
        }
        do {
            try databasePool.write { database in
                try insertSession(session, database: database)
                for stream in streams { try insertStream(stream, database: database) }
                try insertEpoch(epoch, database: database)
                try verifyForeignKeys(database)
            }
        } catch let error as AcquisitionPersistenceError {
            throw error
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw AcquisitionPersistenceError.conflict
        } catch {
            throw AcquisitionPersistenceError.unavailable
        }
    }

    /// Sequenceをtransactionで消費し、同じ範囲を再利用させません。
    /// - Parameters:
    ///   - streamID: 対象Stream。
    ///   - recordCount: 穴のない保存対象件数。
    ///   - expectedStreamRevision: 呼出側が読んだRevision。
    ///   - updatedAt: 更新日時。
    /// - Returns: 新しいChunk ID付き予約。
    /// - Throws: stale、終端Stream、overflow、DB失敗。
    func reserveChunk(streamID: UUID, recordCount: Int64, expectedStreamRevision: Int, updatedAt: Date) throws -> AcquisitionChunkReservation {
        guard recordCount > 0, expectedStreamRevision >= 1 else {
            throw AcquisitionPersistenceError.invalidRequest
        }
        do {
            return try databasePool.write { database in
                guard let row = try Row.fetchOne(
                    database,
                    sql: "SELECT session_id,next_record_sequence,next_chunk_sequence,stream_state FROM active_or_local_acquisition_streams WHERE user_scope_id=? AND stream_id=?",
                    arguments: [scopeString, uuid(streamID)]
                ), let sessionString: String = row["session_id"],
                   let sessionID = UUID(uuidString: sessionString),
                   let first: Int64 = row["next_record_sequence"],
                   let chunkSequence: Int64 = row["next_chunk_sequence"],
                   let state: String = row["stream_state"],
                   state == AcquisitionStream.State.active.rawValue,
                   first <= Int64.max - recordCount else {
                    throw AcquisitionPersistenceError.conflict
                }
                let last = first + recordCount - 1
                try database.execute(
                    sql: "UPDATE acquisition_streams SET next_record_sequence=?,next_chunk_sequence=next_chunk_sequence+1,record_revision=record_revision+1,updated_at_utc=? WHERE user_scope_id=? AND stream_id=? AND record_revision=? AND stream_state='active'",
                    arguments: [last + 1, timestamp(updatedAt), scopeString, uuid(streamID), expectedStreamRevision]
                )
                guard database.changesCount == 1 else { throw AcquisitionPersistenceError.conflict }
                return AcquisitionChunkReservation(
                    chunkID: UUID(),
                    sessionID: sessionID,
                    streamID: streamID,
                    chunkSequence: chunkSequence,
                    firstRecordSequence: first,
                    lastRecordSequence: last
                )
            }
        } catch let error as AcquisitionPersistenceError {
            throw error
        } catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// file確定済み目録のcanonical digestを再計算し、INSERT後に全列を読戻します。
    /// - Parameter entry: file digestと別の目録digestを持つ値。
    /// - Returns: DBから再構成した目録。
    /// - Throws: digest不一致、予約不整合、競合、DB失敗。
    func commitChunk(_ entry: AcquisitionChunkCatalogEntry) throws -> AcquisitionChunkCatalogEntry {
        try validate(entry)
        do {
            return try databasePool.write { database in
                let r = entry.reservation
                guard let stream = try Row.fetchOne(
                    database,
                    sql: "SELECT session_id,next_record_sequence,next_chunk_sequence FROM active_or_local_acquisition_streams WHERE user_scope_id=? AND stream_id=?",
                    arguments: [scopeString, uuid(r.streamID)]
                ), (stream["session_id"] as String) == uuid(r.sessionID),
                   (stream["next_record_sequence"] as Int64) >= r.lastRecordSequence + 1,
                   (stream["next_chunk_sequence"] as Int64) >= r.chunkSequence + 1 else {
                    throw AcquisitionPersistenceError.conflict
                }
                try database.execute(
                    sql: """
                    INSERT INTO log_chunks(user_scope_id,chunk_id,session_id,stream_id,chunk_sequence,clock_epoch_id,first_record_sequence,last_record_sequence,first_monotonic_ns,last_monotonic_ns,record_count,plaintext_size,compressed_size,ciphertext_size,record_format_version,compression_format_version,encryption_format_version,key_version,ciphertext_digest,catalog_digest,relative_path,storage_state,revision,created_at_utc,updated_at_utc)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'available',1,?,?)
                    """,
                    arguments: [scopeString,uuid(r.chunkID),uuid(r.sessionID),uuid(r.streamID),r.chunkSequence,uuid(entry.clockEpochID),r.firstRecordSequence,r.lastRecordSequence,entry.firstMonotonicNanoseconds,entry.lastMonotonicNanoseconds,recordCount(entry),entry.plaintextSize,entry.compressedSize,entry.ciphertextSize,entry.recordFormatVersion,entry.compressionFormatVersion,entry.encryptionFormatVersion,entry.keyVersion,entry.ciphertextDigest,entry.catalogDigest,entry.relativePath,timestamp(entry.createdAt),timestamp(entry.createdAt)]
                )
                guard let row = try Row.fetchOne(database, sql: "SELECT * FROM active_or_local_log_chunks WHERE user_scope_id=? AND chunk_id=?", arguments: [scopeString,uuid(r.chunkID)]) else {
                    throw AcquisitionPersistenceError.catalogCommitFailed
                }
                return try makeEntry(row)
            }
        } catch let error as AcquisitionPersistenceError { throw error }
        catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw AcquisitionPersistenceError.conflict }
        catch { throw AcquisitionPersistenceError.catalogCommitFailed }
    }

    /// 開放Gapを追記し、Raw bytesや例外文はDBへ保存しません。
    /// - Parameter gap: 失われた範囲の安定メタデータ。
    /// - Throws: 重複、FK不整合、DB失敗。
    func recordGap(_ gap: AcquisitionGap) throws {
        do {
            try databasePool.write { database in
                try database.execute(
                    sql: """
                    INSERT INTO acquisition_gaps(user_scope_id,gap_id,session_id,stream_id,reason_code,detection_method,start_boundary_certainty,start_clock_epoch_id,start_monotonic_ns,start_utc,end_clock_epoch_id,end_monotonic_ns,end_utc,end_boundary_certainty,first_missing_sequence,missing_record_count,revision,created_at_utc)
                    VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,?,?,1,?)
                    """,
                    arguments: [scopeString,uuid(gap.gapID),uuid(gap.sessionID),uuid(gap.streamID),gap.reason.rawValue,gap.detectionMethod.rawValue,gap.startCertainty.rawValue,uuid(gap.startClockEpochID),gap.startMonotonicNanoseconds,timestamp(gap.startAt),gap.firstMissingSequence,gap.missingRecordCount,timestamp(gap.createdAt)]
                )
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT { throw AcquisitionPersistenceError.conflict }
        catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// active Vehicleを再確認し、保存確定前のNULL所属を一度だけ更新します。
    /// - Parameters:
    ///   - sessionID: 未割当Session。
    ///   - vehicleID: active Vehicle。
    ///   - expectedSessionRevision: Sessionの期待Revision。
    ///   - expectedVehicleLifecycleRevision: Vehicleの期待Lifecycle Revision。
    /// - Throws: 登録済みVehicleや未割当Sessionを削除せず競合を返します。
    func bind(sessionID: UUID, vehicleID: UUID, expectedSessionRevision: Int, expectedVehicleLifecycleRevision: Int) throws {
        guard expectedSessionRevision >= 1, expectedVehicleLifecycleRevision >= 1 else { throw VehiclePersistenceError.invalidRequest }
        do {
            try databasePool.write { database in
                guard let vehicle = try Row.fetchOne(database, sql: "SELECT lifecycle_state,lifecycle_revision FROM vehicles WHERE user_scope_id=? AND vehicle_id=?", arguments: [scopeString,uuid(vehicleID)]),
                      (vehicle["lifecycle_state"] as String) == "active",
                      (vehicle["lifecycle_revision"] as Int) == expectedVehicleLifecycleRevision else { throw VehiclePersistenceError.conflict }
                if let existing = try Row.fetchOne(database, sql: "SELECT vehicle_id,record_revision FROM active_or_local_acquisition_sessions WHERE user_scope_id=? AND session_id=?", arguments: [scopeString,uuid(sessionID)]),
                   let bound: String = existing["vehicle_id"] {
                    guard bound == uuid(vehicleID) else { throw VehiclePersistenceError.conflict }
                    return
                }
                let updatedAt = timestamp(Date())
                try database.execute(
                    sql: "UPDATE acquisition_sessions SET vehicle_id=?,vehicle_binding_state='registered_confirmed',record_revision=record_revision+1,updated_at_utc=?,updated_by_device_id=updated_by_device_id WHERE user_scope_id=? AND session_id=? AND vehicle_id IS NULL AND disposition_state='pending_decision' AND record_revision=?",
                    arguments: [uuid(vehicleID),updatedAt,scopeString,uuid(sessionID),expectedSessionRevision]
                )
                guard database.changesCount == 1 else { throw VehiclePersistenceError.conflict }
            }
        } catch let error as VehiclePersistenceError { throw error }
        catch { throw VehiclePersistenceError.unavailable }
    }

    /// vehicle_idの有無に依存せず、全StreamとSessionを同じtransactionで終端します。
    /// - Parameters:
    ///   - sessionID: 終端するSession。
    ///   - expectedSessionRevision: 期待Revision。
    ///   - reason: user_stopなら正常、それ以外は復旧要。
    ///   - endedAt: 終端観測日時。
    ///   - deviceID: 更新端末UUID。
    /// - Throws: stale状態またはDB失敗。
    func finishSession(sessionID: UUID, expectedSessionRevision: Int, reason: AcquisitionSession.EndReason, endedAt: Date, deviceID: UUID) throws {
        guard expectedSessionRevision >= 1 else { throw AcquisitionPersistenceError.invalidRequest }
        do {
            try databasePool.write { database in
                let value = timestamp(endedAt)
                let streamState = reason == .userStop ? "stopped" : "interrupted"
                try database.execute(sql: "UPDATE acquisition_streams SET stream_state=?,ended_at_utc=?,record_revision=record_revision+1,updated_at_utc=? WHERE user_scope_id=? AND session_id=? AND stream_state NOT IN ('stopped','interrupted')", arguments: [streamState,value,value,scopeString,uuid(sessionID)])
                let captureState = reason == .userStop ? "ended_cleanly" : "recovery_required"
                let integrityState = reason == .userStop ? "unchecked" : "attention_required"
                try database.execute(sql: "UPDATE acquisition_sessions SET capture_state=?,integrity_state=?,end_reason_code=?,ended_at_utc=?,record_revision=record_revision+1,updated_at_utc=?,updated_by_device_id=? WHERE user_scope_id=? AND session_id=? AND capture_state IN ('recording','stop_requested') AND record_revision=?", arguments: [captureState,integrityState,reason.rawValue,value,value,uuid(deviceID),scopeString,uuid(sessionID),expectedSessionRevision])
                guard database.changesCount == 1 else { throw AcquisitionPersistenceError.conflict }
            }
        } catch let error as AcquisitionPersistenceError { throw error }
        catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// 起動時に進行中Sessionと非終端Streamを異常終端し、IDを返します。
    /// - Parameters:
    ///   - recoveredAt: 復旧観測日時。
    ///   - deviceID: 復旧processの端末ID。
    /// - Returns: recovery_requiredへ変更したSession ID。
    /// - Throws: DB失敗時`unavailable`。
    func recoverInterruptedSessions(at recoveredAt: Date, deviceID: UUID) throws -> [UUID] {
        do {
            return try databasePool.write { database in
                // raw table access: 起動時recoveryは未公開graphも安全に異常終端する保全処理です。
                let ids = try String.fetchAll(database, sql: "SELECT session_id FROM acquisition_sessions WHERE user_scope_id=? AND capture_state IN ('recording','stop_requested')", arguments: [scopeString])
                let value = timestamp(recoveredAt)
                for id in ids {
                    try database.execute(sql: "UPDATE acquisition_streams SET stream_state='interrupted',ended_at_utc=?,record_revision=record_revision+1,updated_at_utc=? WHERE user_scope_id=? AND session_id=? AND stream_state NOT IN ('stopped','interrupted')", arguments: [value,value,scopeString,id])
                    try database.execute(sql: "UPDATE acquisition_sessions SET capture_state='recovery_required',integrity_state='attention_required',end_reason_code='unknown',ended_at_utc=?,record_revision=record_revision+1,updated_at_utc=?,updated_by_device_id=? WHERE user_scope_id=? AND session_id=?", arguments: [value,value,uuid(deviceID),scopeString,id])
                }
                return ids.compactMap(UUID.init(uuidString:))
            }
        } catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// DB目録の照合用参照を返します。
    /// - Returns: 全ChunkのID、Session、path、available状態。
    /// - Throws: DB読取失敗時`unavailable`。
    func chunkCatalogReferences() throws -> [AcquisitionChunkCatalogReference] {
        do {
            return try databasePool.read { database in
                // raw table access: file監査は未公開・旧graphを含む全目録との孤立判定が必要です。
                try Row.fetchAll(database, sql: "SELECT chunk_id,session_id,relative_path,storage_state FROM log_chunks WHERE user_scope_id=?", arguments: [scopeString]).map { row in
                    guard let chunkID = UUID(uuidString: row["chunk_id"]), let sessionID = UUID(uuidString: row["session_id"]) else { throw AcquisitionPersistenceError.unavailable }
                    return AcquisitionChunkCatalogReference(chunkID: chunkID,sessionID: sessionID,relativePath: row["relative_path"],isAvailable: (row["storage_state"] as String) == "available")
                }
            }
        } catch let error as AcquisitionPersistenceError { throw error }
        catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// available目録をmissingへ進め、同じSession／ChunkのFindingを追記します。
    /// - Parameters:
    ///   - reference: 欠落した目録参照。
    ///   - detectedAt: 検出日時。
    /// - Throws: stale状態またはDB失敗。
    func markChunkMissing(_ reference: AcquisitionChunkCatalogReference, detectedAt: Date) throws {
        guard reference.isAvailable else { return }
        do {
            try databasePool.write { database in
                let value = timestamp(detectedAt)
                try database.execute(sql: "UPDATE log_chunks SET storage_state='missing',revision=revision+1,updated_at_utc=? WHERE user_scope_id=? AND chunk_id=? AND storage_state='available'", arguments: [value,scopeString,uuid(reference.chunkID)])
                guard database.changesCount == 1 else { throw AcquisitionPersistenceError.conflict }
                try insertFinding(database: database,kind: .missingFile,sessionID: reference.sessionID,chunkID: reference.chunkID,observedPath: reference.relativePath,quarantinePath: nil,detectedAt: detectedAt)
            }
        } catch let error as AcquisitionPersistenceError { throw error }
        catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// DBへ帰属不能な隔離fileをPayloadなしのFindingとして追記します。
    /// - Parameters:
    ///   - kind: orphanまたはunexpected temporary。
    ///   - observedPath: 発見時の安全な相対path。
    ///   - quarantinePath: 隔離後の安全な相対path。
    ///   - detectedAt: 検出日時。
    /// - Throws: 入力またはDB失敗。
    func recordUncatalogedFinding(kind: StorageIntegrityFindingKind, observedPath: String, quarantinePath: String, detectedAt: Date) throws {
        guard kind != .missingFile, !observedPath.isEmpty, !quarantinePath.isEmpty else { throw AcquisitionPersistenceError.invalidRequest }
        do {
            try databasePool.write { try insertFinding(database: $0,kind: kind,sessionID: nil,chunkID: nil,observedPath: observedPath,quarantinePath: quarantinePath,detectedAt: detectedAt) }
        } catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// Session行をINSERTします。
    private func insertSession(_ session: AcquisitionSession, database: Database) throws {
        try database.execute(sql: "INSERT INTO acquisition_sessions(user_scope_id,session_id,vehicle_id,vehicle_binding_state,capture_state,disposition_state,integrity_state,end_reason_code,started_at_utc,ended_at_utc,reviewed_at_utc,disposition_requested_at_utc,disposition_completed_at_utc,created_by_device_id,record_revision,updated_at_utc,updated_by_device_id) VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,?,?,?,?)", arguments: [scopeString,uuid(session.sessionID),session.vehicleID.map(uuid),session.vehicleBindingState.rawValue,session.captureState.rawValue,session.dispositionState.rawValue,session.integrityState.rawValue,session.endReason?.rawValue,timestamp(session.startedAt),session.endedAt.map(timestamp),uuid(session.createdByDeviceID),session.revision,timestamp(session.updatedAt),uuid(session.updatedByDeviceID)])
    }

    /// Stream行をINSERTします。
    private func insertStream(_ stream: AcquisitionStream, database: Database) throws {
        try database.execute(sql: "INSERT INTO acquisition_streams(user_scope_id,stream_id,session_id,stream_kind,adapter_role,adapter_reference_id,connection_instance_id,stream_state,started_at_utc,ended_at_utc,next_record_sequence,next_chunk_sequence,record_revision,updated_at_utc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)", arguments: [scopeString,uuid(stream.streamID),uuid(stream.sessionID),stream.kind.rawValue,stream.adapterRole.rawValue,stream.adapterReferenceID,uuid(stream.connectionInstanceID),stream.state.rawValue,timestamp(stream.startedAt),stream.endedAt.map(timestamp),stream.nextRecordSequence,stream.nextChunkSequence,stream.revision,timestamp(stream.updatedAt)])
    }

    /// Epoch行をINSERTします。
    private func insertEpoch(_ epoch: AcquisitionClockEpoch, database: Database) throws {
        try database.execute(sql: "INSERT INTO clock_epochs(user_scope_id,clock_epoch_id,session_id,process_instance_id,device_id,monotonic_clock_kind,wall_clock_anchor_utc,anchor_uncertainty_ns,started_at_utc,ended_at_utc,revision) VALUES(?,?,?,?,?,'continuous_host_time',?,?,?,NULL,1)", arguments: [scopeString,uuid(epoch.clockEpochID),uuid(epoch.sessionID),uuid(epoch.processInstanceID),uuid(epoch.deviceID),timestamp(epoch.wallClockAnchor),epoch.anchorUncertaintyNanoseconds,timestamp(epoch.startedAt)])
    }

    /// canonical digest、範囲、相対pathを検証します。
    private func validate(_ entry: AcquisitionChunkCatalogEntry) throws {
        guard entry.ciphertextDigest.count == 32, entry.catalogDigest.count == 32,
              entry.catalogDigest == (try catalogDigester.digest(for: entry)),
              entry.ciphertextSize > 0,
              entry.firstMonotonicNanoseconds <= entry.lastMonotonicNanoseconds else { throw AcquisitionPersistenceError.invalidRequest }
    }

    /// DB行をDomain目録へ戻します。
    private func makeEntry(_ row: Row) throws -> AcquisitionChunkCatalogEntry {
        guard let chunkID = UUID(uuidString: row["chunk_id"]), let sessionID = UUID(uuidString: row["session_id"]), let streamID = UUID(uuidString: row["stream_id"]), let epochID = UUID(uuidString: row["clock_epoch_id"]), let createdAt = GRDBVehicleDateCodec.date(from: row["created_at_utc"]) else { throw AcquisitionPersistenceError.catalogCommitFailed }
        return AcquisitionChunkCatalogEntry(reservation: .init(chunkID: chunkID,sessionID: sessionID,streamID: streamID,chunkSequence: row["chunk_sequence"],firstRecordSequence: row["first_record_sequence"],lastRecordSequence: row["last_record_sequence"]),clockEpochID: epochID,firstMonotonicNanoseconds: row["first_monotonic_ns"],lastMonotonicNanoseconds: row["last_monotonic_ns"],plaintextSize: row["plaintext_size"],compressedSize: row["compressed_size"],ciphertextSize: row["ciphertext_size"],recordFormatVersion: row["record_format_version"],compressionFormatVersion: row["compression_format_version"],encryptionFormatVersion: row["encryption_format_version"],keyVersion: row["key_version"],ciphertextDigest: row["ciphertext_digest"],catalogDigest: row["catalog_digest"],relativePath: row["relative_path"],createdAt: createdAt)
    }

    /// Foreign Key整合性をtransaction内で検証します。
    private func verifyForeignKeys(_ database: Database) throws { guard try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty else { throw AcquisitionPersistenceError.unavailable } }
    /// 非機密な保全Findingを追記します。
    private func insertFinding(database: Database, kind: StorageIntegrityFindingKind, sessionID: UUID?, chunkID: UUID?, observedPath: String, quarantinePath: String?, detectedAt: Date) throws {
        try database.execute(sql: "INSERT INTO storage_integrity_findings(user_scope_id,finding_id,session_id,catalog_chunk_id,observed_session_id,observed_chunk_id,finding_kind,resolution_state,observed_relative_path,quarantine_relative_path,diagnostic_id,detected_at_utc,resolved_at_utc,revision) VALUES(?,?,?,?,NULL,NULL,?,'quarantined',?,?,?,?,NULL,1)", arguments: [scopeString,uuid(UUID()),sessionID.map(uuid),chunkID.map(uuid),kind.rawValue,observedPath,quarantinePath,uuid(UUID()),timestamp(detectedAt)])
    }
    /// UUIDをDB canonical文字列へ変換します。
    private func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    /// Dateを固定UTC文字列へ変換します。
    private func timestamp(_ value: Date) -> String { GRDBVehicleDateCodec.string(from: value) }
    /// 予約範囲の件数を返します。
    private func recordCount(_ entry: AcquisitionChunkCatalogEntry) -> Int64 { entry.reservation.lastRecordSequence - entry.reservation.firstRecordSequence + 1 }
}
