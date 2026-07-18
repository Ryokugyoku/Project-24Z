import Foundation

/// 車両未割当のままSessionを既存Storage順序で終了する狭い能力境界です。
protocol UnassignedSessionRepository {
    /// 車両所属の有無を変更せずSessionとStreamを終端します。
    /// - Parameters:
    ///   - sessionID: 終端するSession UUID。
    ///   - expectedSessionRevision: 期待Session Revision。
    ///   - reason: 既存Storageの終端理由。
    ///   - endedAt: 終端日時。
    ///   - deviceID: 更新端末UUID。
    /// - Throws: stale状態または保存利用不能。
    func finishSession(
        sessionID: UUID,
        expectedSessionRevision: Int,
        reason: AcquisitionSession.EndReason,
        endedAt: Date,
        deviceID: UUID
    ) throws
}
