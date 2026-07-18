/// PID Pollingの観測上の相対優先度です。
nonisolated enum AdaptivePollingPriority: Int, Equatable, Hashable, Sendable {
    /// 高い観測頻度を許可された候補です。
    case fast = 0
    /// 通常の継続観測です。
    case normal = 1
    /// 低頻度でも再訪が必要な候補です。
    case slow = 2
    /// 明示要求時だけ対象にする候補です。
    case onDemand = 3
    /// 失敗後の上限付き再試行候補です。
    case probeBackoff = 4
}
