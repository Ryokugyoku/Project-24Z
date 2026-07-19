import Foundation
@testable import Project_24Z

/// Session transaction境界の記録Fakeです。
final class FakeAcquisitionSessionStarter: AcquisitionSessionStarting, @unchecked Sendable {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStartEventRecorder

    /// 固定Session IDです。
    let sessionID = UUID()

    /// commit回数です。
    private(set) var callCount = 0

    /// 最後にSecondaryを含めたかを示します。
    private(set) var includedSecondary: Bool?

    /// Fakeを構成します。
    /// - Parameter recorder: 共通Recorder。
    init(recorder: AcquisitionStartEventRecorder) { self.recorder = recorder }

    /// commitを記録します。
    /// - Parameters:
    ///   - scope: 使用しないscope。
    ///   - primary: 使用しないPrimary。
    ///   - secondary: Stream集合確認用Secondary。
    ///   - startedAt: 使用しない日時。
    /// - Returns: 固定Session ID。
    func startSession(in scope: LocalDeviceScope, primary: PreparedAdapterConnection, secondary: PreparedAdapterConnection?, startedAt: Date) async throws -> UUID {
        callCount += 1
        includedSecondary = secondary != nil
        recorder.append("commit")
        return sessionID
    }
}
