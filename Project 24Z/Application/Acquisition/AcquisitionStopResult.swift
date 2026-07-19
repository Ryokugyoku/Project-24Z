import Foundation

/// Application停止境界がDashboardへ返す終端結果です。
nonisolated enum AcquisitionStopResult: Equatable, Sendable {
    /// StreamとSessionを正常終了として確定しました。
    case stopped(sessionID: UUID)
    /// 正常終了を捏造せず復旧要状態へ確定しました。
    case recoveryRequired(sessionID: UUID, failure: AcquisitionStopFailure)
    /// DB障害等により復旧要状態の確定も確認できませんでした。
    case stateUnknown(sessionID: UUID, failure: AcquisitionStopFailure)
    /// 同じCoordinatorが既に停止処理を実行中です。
    case alreadyStopping(sessionID: UUID)
}

/// Dashboardが依存する型付き停止Action境界です。
nonisolated protocol AcquisitionStopCoordinating: Sendable {
    /// 一つの収集中Sessionを安全停止します。
    /// - Parameter sessionID: 対象Session ID。
    /// - Returns: 正常終了、復旧要、または状態不明。
    func stop(sessionID: UUID) async -> AcquisitionStopResult
}
