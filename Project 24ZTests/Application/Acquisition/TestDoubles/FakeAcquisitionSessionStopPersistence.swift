import Foundation
@testable import Project_24Z

/// Session停止transactionを観測・失敗注入するFakeです。
final class FakeAcquisitionSessionStopPersistence: AcquisitionSessionStopPersisting, @unchecked Sendable {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStopEventRecorder

    /// 停止要求回数です。
    private(set) var requestCount = 0

    /// 正常終了確定回数です。
    private(set) var completionCount = 0

    /// 復旧要確定回数です。
    private(set) var recoveryCount = 0

    /// 正常終了確定を失敗させるかを示します。
    var completionFails = false

    /// 停止要求確定を失敗させるかを示します。
    var requestFails = false

    /// 復旧要確定を失敗させるかを示します。
    var recoveryFails = false

    /// Fakeを構成します。
    /// - Parameter recorder: 共通Recorder。
    init(recorder: AcquisitionStopEventRecorder) { self.recorder = recorder }

    /// 停止要求transactionを記録します。
    /// - Parameters:
    ///   - sessionID: 対象Session ID。
    ///   - requestedAt: 使用しない日時。
    ///   - deviceID: 使用しない端末ID。
    /// - Returns: Revision 2の停止Context。
    func requestStop(sessionID: UUID, requestedAt: Date, deviceID: UUID) throws -> AcquisitionStopContext {
        requestCount += 1
        recorder.append("request-stop")
        if requestFails { throw AcquisitionPersistenceError.unavailable }
        return .init(sessionID: sessionID, sessionRevision: 2)
    }

    /// 正常終了確定を記録します。
    /// - Parameters:
    ///   - context: 停止Context。
    ///   - endedAt: 使用しない日時。
    ///   - deviceID: 使用しない端末ID。
    /// - Throws: `completionFails`なら保存失敗。
    func completeStop(_ context: AcquisitionStopContext, endedAt: Date, deviceID: UUID) throws {
        completionCount += 1
        recorder.append("complete-stop")
        if completionFails { throw AcquisitionPersistenceError.unavailable }
    }

    /// 復旧要確定を記録します。
    /// - Parameters:
    ///   - sessionID: 対象Session ID。
    ///   - reason: 異常終端理由。
    ///   - endedAt: 使用しない日時。
    ///   - deviceID: 使用しない端末ID。
    /// - Throws: `recoveryFails`なら保存失敗。
    func requireRecovery(sessionID: UUID, reason: AcquisitionSession.EndReason, endedAt: Date, deviceID: UUID) throws {
        recoveryCount += 1
        recorder.append("require-recovery")
        if recoveryFails { throw AcquisitionPersistenceError.unavailable }
    }
}
