import Foundation

/// Session目録とimmutable Chunk catalogをGRDBへ保存する能力です。
protocol AcquisitionRepository {
    /// Session、PID／Raw CAN Stream、Epochを一transactionで開始します。
    func start(session: AcquisitionSession, streams: [AcquisitionStream], epoch: AcquisitionClockEpoch) throws
    /// StreamのRecord／Chunk Sequenceを再利用不能に予約します。
    func reserveChunk(streamID: UUID, recordCount: Int64, expectedStreamRevision: Int, updatedAt: Date) throws -> AcquisitionChunkReservation
    /// file検証済みの目録をcommitし、DBから読戻します。
    func commitChunk(_ entry: AcquisitionChunkCatalogEntry) throws -> AcquisitionChunkCatalogEntry
    /// 欠損を非破壊で追記します。
    func recordGap(_ gap: AcquisitionGap) throws
    /// 未割当Sessionをactive Vehicleへ一度だけ所属させます。
    func bind(sessionID: UUID, vehicleID: UUID, expectedSessionRevision: Int, expectedVehicleLifecycleRevision: Int) throws
    /// 車両未割当を含むSessionと全Streamを明示的に終端します。
    func finishSession(sessionID: UUID, expectedSessionRevision: Int, reason: AcquisitionSession.EndReason, endedAt: Date, deviceID: UUID) throws
    /// 進行中Sessionを再起動検出として終端し、元行を保持します。
    func recoverInterruptedSessions(at recoveredAt: Date, deviceID: UUID) throws -> [UUID]
    /// DBとfileの双方向照合に必要な目録参照を返します。
    func chunkCatalogReferences() throws -> [AcquisitionChunkCatalogReference]
    /// file欠落目録をmissingへ移し、Findingを同じtransactionで作ります。
    func markChunkMissing(_ reference: AcquisitionChunkCatalogReference, detectedAt: Date) throws
    /// DB行のないfileまたはstaging隔離結果をFindingとして追記します。
    func recordUncatalogedFinding(kind: StorageIntegrityFindingKind, observedPath: String, quarantinePath: String, detectedAt: Date) throws
}
