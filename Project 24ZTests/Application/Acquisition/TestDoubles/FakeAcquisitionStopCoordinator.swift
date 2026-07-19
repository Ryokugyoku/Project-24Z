import Foundation
@testable import Project_24Z

/// Dashboardからの型付き停止Actionを記録するFakeです。
actor FakeAcquisitionStopCoordinator: AcquisitionStopCoordinating {
    /// 停止呼出し回数です。
    private(set) var callCount = 0

    /// 返す停止結果です。
    let result: AcquisitionStopResult

    /// Fakeを構成します。
    /// - Parameter result: 返す停止結果。
    init(result: AcquisitionStopResult) { self.result = result }

    /// 停止呼出しを記録します。
    /// - Parameter sessionID: 対象Session ID。
    /// - Returns: 設定済み結果。
    func stop(sessionID: UUID) async -> AcquisitionStopResult {
        callCount += 1
        return result
    }
}
