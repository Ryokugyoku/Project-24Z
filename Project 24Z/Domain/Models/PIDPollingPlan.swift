import Foundation

/// support Snapshotから作られた一接続内だけ有効なPolling計画です。
nonisolated struct PIDPollingPlan: Equatable, Sendable {
    /// plan世代です。
    let generation: UInt64
    /// 接続世代です。
    let connectionGeneration: ConnectionGeneration
    /// 根拠support Snapshotです。
    let supportSnapshotID: UUID
    /// 現在の候補です。
    let candidates: [AdaptivePollingScheduler.Candidate]
}
