import Foundation

/// 停止要求transactionが確定したSessionと期待Revisionを表します。
nonisolated struct AcquisitionStopContext: Equatable, Sendable {
    /// 停止対象Session IDです。
    let sessionID: UUID

    /// `stop_requested`確定後のSession Revisionです。
    let sessionRevision: Int
}
