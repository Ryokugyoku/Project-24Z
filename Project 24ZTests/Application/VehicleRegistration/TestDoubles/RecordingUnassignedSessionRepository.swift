import Foundation
@testable import Project_24Z

/// 未割当Session終了を記録するFakeです。
final class RecordingUnassignedSessionRepository: UnassignedSessionRepository {
    /// 終了呼出し回数です。
    private(set) var callCount = 0
    /// 最後に終了したSession UUIDです。
    private(set) var sessionID: UUID?

    /// 未割当Sessionの終了を記録します。
    func finishSession(
        sessionID: UUID,
        expectedSessionRevision: Int,
        reason: AcquisitionSession.EndReason,
        endedAt: Date,
        deviceID: UUID
    ) throws {
        callCount += 1
        self.sessionID = sessionID
    }
}
