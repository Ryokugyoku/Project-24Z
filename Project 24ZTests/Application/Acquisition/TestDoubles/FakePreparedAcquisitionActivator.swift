import Foundation
@testable import Project_24Z

/// commit後の取得開始を記録するFakeです。
final class FakePreparedAcquisitionActivator: PreparedAcquisitionActivating, @unchecked Sendable {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStartEventRecorder

    /// activate回数です。
    private(set) var callCount = 0

    /// Fakeを構成します。
    /// - Parameter recorder: 共通Recorder。
    init(recorder: AcquisitionStartEventRecorder) { self.recorder = recorder }

    /// activateを記録します。
    /// - Parameters:
    ///   - sessionID: commit済みSession ID。
    ///   - primary: Primary接続。
    ///   - secondary: 任意Secondary接続。
    func activate(sessionID: UUID, primary: PreparedAdapterConnection, secondary: PreparedAdapterConnection?) async throws {
        callCount += 1
        recorder.append("activate")
    }
}
