import Foundation

/// 注入された実測済み制約に従い、公平な次Requestを選ぶ純粋Schedulerです。
nonisolated struct AdaptivePollingScheduler: Sendable {
    /// 一つのPID／ECU候補の可変でない選択Snapshotです。
    struct Candidate: Equatable, Sendable {
        /// PID／ECU Identityです。
        let identity: PIDSignalIdentity
        /// 相対優先度です。
        let priority: AdaptivePollingPriority
        /// 次に選択可能な時刻です。
        let nextEligibleAt: Date
        /// starvation防止の再訪期限です。
        let latestRevisitAt: Date
        /// 連続失敗回数です。
        let consecutiveFailures: Int
        /// 明示on-demand要求の有無です。
        let isDemanded: Bool
    }

    /// 実測Hard Gate後にだけ注入できる選択制約です。
    struct Constraints: Equatable, Sendable {
        /// 同一ECUを連続選択できる最大回数です。
        let maximumConsecutiveSelectionsPerECU: Int
        /// fastが連続して全slotを占有できる最大回数です。
        let maximumConsecutiveFastSelections: Int
        /// retry対象を再選択できる最大失敗回数です。
        let maximumRetryCount: Int

        /// 正の制約だけを受理します。
        /// - Returns: 全値が安全な下限を満たす場合は`true`。
        var isUsable: Bool {
            maximumConsecutiveSelectionsPerECU > 0 && maximumConsecutiveFastSelections > 0 && maximumRetryCount >= 0
        }
    }

    /// 直前までの公平性状態です。
    struct FairnessState: Equatable, Sendable {
        /// 直前に選択したECUです。
        let lastECUSource: [UInt8]?
        /// 同じECUの連続選択数です。
        let consecutiveECUSelections: Int
        /// fastの連続選択数です。
        let consecutiveFastSelections: Int
    }

    /// Schedulerが判断した次の一件と更新後の公平性です。
    struct Selection: Equatable, Sendable {
        /// 選択した候補です。
        let candidate: Candidate
        /// 次回へ渡す公平性状態です。
        let fairness: FairnessState
    }

    /// 現在時刻で送信可能な候補をdeadline、公平性、優先度の順に選びます。
    /// - Parameters:
    ///   - candidates: active plan内のPID／ECU候補。
    ///   - now: 選択基準時刻。
    ///   - constraints: 実測済み制約。未確定値は渡しません。
    ///   - fairness: 直前までの公平性状態。
    /// - Returns: 選択可能な一件。制約未確定または候補なしならnil。
    func selectNext(
        from candidates: [Candidate],
        now: Date,
        constraints: Constraints?,
        fairness: FairnessState
    ) -> Selection? {
        guard let constraints, constraints.isUsable else { return nil }
        let eligible = candidates.filter { candidate in
            candidate.nextEligibleAt <= now &&
                candidate.consecutiveFailures <= constraints.maximumRetryCount &&
                (candidate.priority != .onDemand || candidate.isDemanded)
        }
        guard !eligible.isEmpty else { return nil }

        let overdue = eligible.filter { $0.latestRevisitAt <= now }
        let pool = overdue.isEmpty ? eligible : overdue
        let ecuFairPool: [Candidate]
        if fairness.consecutiveECUSelections >= constraints.maximumConsecutiveSelectionsPerECU,
           let last = fairness.lastECUSource,
           pool.contains(where: { $0.identity.ecuSource != last }) {
            ecuFairPool = pool.filter { $0.identity.ecuSource != last }
        } else {
            ecuFairPool = pool
        }
        let fastFairPool: [Candidate]
        if fairness.consecutiveFastSelections >= constraints.maximumConsecutiveFastSelections,
           ecuFairPool.contains(where: { $0.priority != .fast }) {
            fastFairPool = ecuFairPool.filter { $0.priority != .fast }
        } else {
            fastFairPool = ecuFairPool
        }
        guard let selected = fastFairPool.sorted(by: compare).first else { return nil }
        let sameECU = selected.identity.ecuSource == fairness.lastECUSource
        return Selection(
            candidate: selected,
            fairness: FairnessState(
                lastECUSource: selected.identity.ecuSource,
                consecutiveECUSelections: sameECU ? fairness.consecutiveECUSelections + 1 : 1,
                consecutiveFastSelections: selected.priority == .fast ? fairness.consecutiveFastSelections + 1 : 0
            )
        )
    }

    /// deadline、優先度、安定Identityの順で候補を比較します。
    /// - Parameters:
    ///   - lhs: 左候補。
    ///   - rhs: 右候補。
    /// - Returns: 左候補を先に選ぶ場合は`true`。
    private func compare(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.latestRevisitAt != rhs.latestRevisitAt { return lhs.latestRevisitAt < rhs.latestRevisitAt }
        if lhs.priority.rawValue != rhs.priority.rawValue { return lhs.priority.rawValue < rhs.priority.rawValue }
        if lhs.identity.ecuSource != rhs.identity.ecuSource { return lhs.identity.ecuSource.lexicographicallyPrecedes(rhs.identity.ecuSource) }
        if lhs.identity.serviceOrMode != rhs.identity.serviceOrMode { return lhs.identity.serviceOrMode < rhs.identity.serviceOrMode }
        return lhs.identity.parameter < rhs.identity.parameter
    }
}
