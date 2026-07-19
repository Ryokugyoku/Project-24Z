import Foundation

/// SessionとStreamの停止状態をGRDB正本へ遷移させる能力です。
nonisolated protocol AcquisitionSessionStopPersisting: Sendable {
    /// Sessionと全非終端Streamを一transactionで`stop_requested`へ進めます。
    /// - Parameters:
    ///   - sessionID: 収集中のSession ID。
    ///   - requestedAt: 停止要求を確定する日時。
    ///   - deviceID: 更新端末ID。
    /// - Returns: 最終停止transactionに使う確定済みRevision。
    /// - Throws: 非収集中、競合、またはDB利用不能。
    func requestStop(sessionID: UUID, requestedAt: Date, deviceID: UUID) throws -> AcquisitionStopContext

    /// 全queueと確定可能Chunkの処理後にだけ正常終了を確定します。
    /// - Parameters:
    ///   - context: `stop_requested`確定結果。
    ///   - endedAt: 正常終了確定日時。
    ///   - deviceID: 更新端末ID。
    /// - Throws: stale状態またはDB利用不能。既存Chunkは削除しません。
    func completeStop(_ context: AcquisitionStopContext, endedAt: Date, deviceID: UUID) throws

    /// 停止途中の障害を正常終了へ昇格せず`recovery_required`へ終端します。
    /// - Parameters:
    ///   - sessionID: 対象Session ID。
    ///   - reason: 正常停止以外の安定理由。
    ///   - endedAt: 異常終端を観測した日時。
    ///   - deviceID: 更新端末ID。
    /// - Throws: DB状態が確定不能な場合。既存Session、Chunk、fileは削除しません。
    func requireRecovery(sessionID: UUID, reason: AcquisitionSession.EndReason, endedAt: Date, deviceID: UUID) throws
}
