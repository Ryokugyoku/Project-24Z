@testable import Project_24Z

/// 開始前検査の成功・失敗Fakeです。
struct FakeAcquisitionStartPreflight: AcquisitionStartPreflightChecking {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStartEventRecorder

    /// 投げる失敗。`nil`なら成功します。
    let failure: AcquisitionStartFailure?

    /// Sessionを作らずfixture結果を返します。
    /// - Throws: 設定済み失敗。
    func checkStartEligibility() async throws {
        recorder.append("preflight")
        if let failure { throw failure }
    }
}
