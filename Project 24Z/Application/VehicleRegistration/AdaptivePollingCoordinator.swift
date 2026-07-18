import Foundation

/// plan、Generation、batch degradeを直列化するApplication actorです。
actor AdaptivePollingCoordinator {
    /// stale tokenまたは利用不能計画を表す安定Errorです。
    enum Error: Swift.Error, Equatable {
        case staleGeneration
        case stalePlan
        case noEligibleCandidate
    }

    private let runtime: any PIDVehicleRuntime
    private let scheduler: AdaptivePollingScheduler
    private var plan: PIDPollingPlan?
    private var fairness = AdaptivePollingScheduler.FairnessState(
        lastECUSource: nil,
        consecutiveECUSelections: 0,
        consecutiveFastSelections: 0
    )
    private var degradedBatchIdentities: Set<PIDSignalIdentity> = []

    /// Runtimeと純粋Schedulerを接続します。
    /// - Parameters:
    ///   - runtime: 型付きPID Runtime。
    ///   - scheduler: 公平性規則。
    init(runtime: any PIDVehicleRuntime, scheduler: AdaptivePollingScheduler = AdaptivePollingScheduler()) {
        self.runtime = runtime
        self.scheduler = scheduler
    }

    /// 新しいplanを唯一のcurrent planとして置換します。
    /// - Parameter plan: support Snapshot由来のplan。
    func install(_ plan: PIDPollingPlan) {
        self.plan = plan
        fairness = .init(lastECUSource: nil, consecutiveECUSelections: 0, consecutiveFastSelections: 0)
        degradedBatchIdentities.removeAll()
    }

    /// pause、stop、再接続時に旧planを破棄します。
    func invalidate() {
        plan = nil
        degradedBatchIdentities.removeAll()
    }

    /// 次候補を選び、batch失敗または曖昧応答では全候補をsingleへ戻します。
    /// - Parameters:
    ///   - now: Scheduler基準時刻。
    ///   - constraints: 実測済み制約。
    ///   - expectedPlanGeneration: 呼出側が保持するplan世代。
    ///   - expectedConnectionGeneration: 呼出側が保持する接続世代。
    ///   - batchCandidates: 実証済みbatch capabilityが示した候補。空ならsingleだけを使います。
    /// - Returns: Rawを保持した個別結果列。
    /// - Throws: stale token、候補なし、Runtime失敗。
    func pollNext(
        now: Date,
        constraints: AdaptivePollingScheduler.Constraints?,
        expectedPlanGeneration: UInt64,
        expectedConnectionGeneration: ConnectionGeneration,
        batchCandidates: [PIDSignalIdentity]
    ) async throws -> [PIDPollingResponse] {
        guard let plan else { throw Error.stalePlan }
        guard plan.generation == expectedPlanGeneration else { throw Error.stalePlan }
        guard plan.connectionGeneration == expectedConnectionGeneration else { throw Error.staleGeneration }
        guard let selection = scheduler.selectNext(from: plan.candidates, now: now, constraints: constraints, fairness: fairness) else {
            throw Error.noEligibleCandidate
        }
        fairness = selection.fairness
        let selected = selection.candidate.identity
        let batch = batchCandidates.filter {
            $0.ecuSource == selected.ecuSource && !degradedBatchIdentities.contains($0)
        }
        guard batch.count > 1, batch.contains(selected) else {
            return [try await runtime.pollSingle(identity: selected, generation: expectedConnectionGeneration)]
        }
        do {
            let response = try await runtime.pollBatch(identities: batch, generation: expectedConnectionGeneration)
            guard response.isUsable else {
                degradedBatchIdentities.formUnion(batch)
                return try await pollSingles(batch, generation: expectedConnectionGeneration)
            }
            return [response]
        } catch {
            degradedBatchIdentities.formUnion(batch)
            return try await pollSingles(batch, generation: expectedConnectionGeneration)
        }
    }

    /// batch候補を一件ずつ実行します。
    /// - Parameters:
    ///   - identities: singleへ戻す候補。
    ///   - generation: current接続Generation。
    /// - Returns: 各single結果。
    /// - Throws: single Runtime失敗。
    private func pollSingles(
        _ identities: [PIDSignalIdentity],
        generation: ConnectionGeneration
    ) async throws -> [PIDPollingResponse] {
        var responses: [PIDPollingResponse] = []
        for identity in identities {
            responses.append(try await runtime.pollSingle(identity: identity, generation: generation))
        }
        return responses
    }
}
