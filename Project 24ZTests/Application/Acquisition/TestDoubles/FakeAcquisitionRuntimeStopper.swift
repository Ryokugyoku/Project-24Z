import Foundation
@testable import Project_24Z

/// PID、Raw CAN、callback停止を観測・失敗注入するFakeです。
final class FakeAcquisitionRuntimeStopper: AcquisitionRuntimeStopping, @unchecked Sendable {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStopEventRecorder

    /// PID停止を失敗させるかを示します。
    var pidStopFails = false

    /// Raw CAN停止を失敗させるかを示します。
    var rawStopFails = false

    /// Fakeを構成します。
    /// - Parameter recorder: 共通Recorder。
    init(recorder: AcquisitionStopEventRecorder) { self.recorder = recorder }

    /// PID要求停止を記録します。
    /// - Parameter sessionID: 使用しないSession ID。
    /// - Throws: `pidStopFails`なら通信失敗。
    func stopPIDRequests(sessionID: UUID) async throws {
        recorder.append("stop-pid")
        if pidStopFails { throw AcquisitionStopFailure.communicationFailure }
    }

    /// Raw CAN停止を記録します。
    /// - Parameter sessionID: 使用しないSession ID。
    /// - Throws: `rawStopFails`なら通信失敗。
    func stopRawCANReception(sessionID: UUID) async throws {
        recorder.append("stop-raw-can")
        if rawStopFails { throw AcquisitionStopFailure.communicationFailure }
    }

    /// callback失効を記録します。
    /// - Parameter sessionID: 使用しないSession ID。
    func invalidateCallbacks(sessionID: UUID) async {
        recorder.append("invalidate-callbacks")
    }

    /// Session終端後のTransport closeを記録します。
    /// - Parameter sessionID: 使用しないSession ID。
    func closeTransport(sessionID: UUID) async {
        recorder.append("close-transport")
    }
}
