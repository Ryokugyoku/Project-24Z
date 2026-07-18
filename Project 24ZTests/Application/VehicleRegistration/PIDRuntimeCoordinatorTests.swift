import Foundation
import Testing
@testable import Project_24Z

/// PID Runtime接続のHard Gate、single fallback、stale planを検証します。
struct PIDRuntimeCoordinatorTests {
    /// 未確定CatalogではRuntimeへ探索をdispatchしません。
    @Test
    func blockedCatalogStopsSupportDiscovery() async {
        let runtime = FakePIDVehicleRuntime()
        let coordinator = PIDSupportDiscoveryCoordinator(runtime: runtime)
        let catalog = PIDCatalogSnapshot(version: "blocked", availability: .blocked, entries: [])
        await #expect(throws: PIDSupportDiscoveryCoordinator.Error.catalogBlocked) {
            try await coordinator.discover(catalog: catalog, generation: .init(value: 1), attemptID: UUID())
        }
    }

    /// Production unavailable Runtimeは承認済み形状でもcommand送信前に拒否します。
    @Test
    func productionUnavailableRuntimeNeverProducesFixtureSuccess() async {
        let runtime = UnavailablePIDVehicleRuntime()
        let value = identity(ecu: [1], parameter: 1)
        let catalog = PIDCatalogSnapshot(
            version: "approved-shape-only",
            availability: .approved,
            entries: [.init(identity: value, priority: .normal)]
        )

        await #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try await runtime.discoverSupport(
                catalog: catalog,
                generation: .init(value: 1),
                attemptID: UUID()
            )
        }
        await #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try await runtime.pollSingle(identity: value, generation: .init(value: 1))
        }
    }

    /// 曖昧なbatch結果を全候補のsingle Requestへfallbackします。
    @Test
    func unusableBatchFallsBackToSingleRequests() async throws {
        let first = identity(ecu: [1], parameter: 1)
        let second = identity(ecu: [1], parameter: 2)
        let runtime = FakePIDVehicleRuntime(
            batchResponse: .init(requestKind: .batch, identities: [first, second], rawResponse: Data([9]), isUsable: false)
        )
        let coordinator = AdaptivePollingCoordinator(runtime: runtime)
        let plan = PIDPollingPlan(
            generation: 7,
            connectionGeneration: .init(value: 3),
            supportSnapshotID: UUID(),
            candidates: [candidate(first), candidate(second)]
        )
        await coordinator.install(plan)
        let responses = try await coordinator.pollNext(
            now: .now,
            constraints: .init(maximumConsecutiveSelectionsPerECU: 2, maximumConsecutiveFastSelections: 2, maximumRetryCount: 1),
            expectedPlanGeneration: 7,
            expectedConnectionGeneration: .init(value: 3),
            batchCandidates: [first, second]
        )
        #expect(responses.count == 2)
        #expect(await runtime.batchRequests.count == 1)
        #expect(await runtime.singleRequests == [first, second])
    }

    /// batch capability候補がない場合は最初からsingleだけを使います。
    @Test
    func unverifiedBatchUsesSingleOnly() async throws {
        let value = identity(ecu: [1], parameter: 1)
        let runtime = FakePIDVehicleRuntime()
        let coordinator = AdaptivePollingCoordinator(runtime: runtime)
        await coordinator.install(.init(generation: 1, connectionGeneration: .init(value: 1), supportSnapshotID: UUID(), candidates: [candidate(value)]))
        _ = try await coordinator.pollNext(
            now: .now,
            constraints: .init(maximumConsecutiveSelectionsPerECU: 1, maximumConsecutiveFastSelections: 1, maximumRetryCount: 1),
            expectedPlanGeneration: 1,
            expectedConnectionGeneration: .init(value: 1),
            batchCandidates: []
        )
        #expect(await runtime.batchRequests.isEmpty)
        #expect(await runtime.singleRequests == [value])
    }

    /// 再接続Generationと旧plan世代を拒否します。
    @Test
    func stalePlanAndGenerationAreRejected() async {
        let runtime = FakePIDVehicleRuntime()
        let coordinator = AdaptivePollingCoordinator(runtime: runtime)
        let value = identity(ecu: [1], parameter: 1)
        await coordinator.install(.init(generation: 2, connectionGeneration: .init(value: 4), supportSnapshotID: UUID(), candidates: [candidate(value)]))
        await #expect(throws: AdaptivePollingCoordinator.Error.stalePlan) {
            try await coordinator.pollNext(now: .now, constraints: nil, expectedPlanGeneration: 1, expectedConnectionGeneration: .init(value: 4), batchCandidates: [])
        }
        await #expect(throws: AdaptivePollingCoordinator.Error.staleGeneration) {
            try await coordinator.pollNext(now: .now, constraints: nil, expectedPlanGeneration: 2, expectedConnectionGeneration: .init(value: 3), batchCandidates: [])
        }
    }

    /// テスト用Identityを作ります。製品Catalog値ではありません。
    private func identity(ecu: [UInt8], parameter: UInt8) -> PIDSignalIdentity {
        .init(namespace: .standardOBD, serviceOrMode: 1, parameter: parameter, ecuSource: ecu, diagnosticProtocolKind: "test", decoderBundleVersion: "test")
    }

    /// 現在選択可能なテスト候補を作ります。
    private func candidate(_ identity: PIDSignalIdentity) -> AdaptivePollingScheduler.Candidate {
        .init(identity: identity, priority: .normal, nextEligibleAt: .distantPast, latestRevisitAt: .distantFuture, consecutiveFailures: 0, isDemanded: true)
    }
}
