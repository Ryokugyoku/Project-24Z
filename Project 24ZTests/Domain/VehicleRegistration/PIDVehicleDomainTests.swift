import Foundation
import Testing
@testable import Project_24Z

/// PID identity、Scheduler、Scan、Validation、重複判定の純粋Domain契約を検証します。
struct PIDVehicleDomainTests {
    /// ECU、protocol、Decoder Version、namespaceの差をIdentityが保持します。
    @Test
    func pidIdentityKeepsAllSeriesDimensionsDistinct() {
        let base = identity(ecu: [1], namespace: .standardOBD)
        #expect(base != identity(ecu: [2], namespace: .standardOBD))
        #expect(base != identity(ecu: [1], namespace: .manufacturerSpecific))
        #expect(base != identity(ecu: [1], namespace: .rawCAN))
        #expect(base != PIDSignalIdentity(namespace: .standardOBD, serviceOrMode: 1, parameter: 2, ecuSource: [1], diagnosticProtocolKind: "other", decoderBundleVersion: "v1"))
        #expect(base != PIDSignalIdentity(namespace: .standardOBD, serviceOrMode: 1, parameter: 2, ecuSource: [1], diagnosticProtocolKind: "protocol", decoderBundleVersion: "v2"))
    }

    /// 未確定Catalogは定義をProduction探索へ公開しません。
    @Test
    func blockedCatalogExposesNoApprovedEntries() {
        let catalog = PIDCatalogSnapshot(
            version: "unapproved",
            availability: .blocked,
            entries: [.init(identity: identity(ecu: [1]), priority: .normal)]
        )
        #expect(catalog.entries.count == 1)
        #expect(catalog.approvedEntries.isEmpty)
    }

    /// deadline超過slowをfastより優先し、starvationを防ぎます。
    @Test
    func schedulerPrioritizesOverdueSlowCandidate() {
        let now = Date(timeIntervalSince1970: 100)
        let scheduler = AdaptivePollingScheduler()
        let candidates = [
            candidate(identity: identity(ecu: [1]), priority: .fast, eligible: 0, revisit: 200),
            candidate(identity: identity(ecu: [2]), priority: .slow, eligible: 0, revisit: 99)
        ]
        let selection = scheduler.selectNext(
            from: candidates,
            now: now,
            constraints: constraints,
            fairness: .init(lastECUSource: [1], consecutiveECUSelections: 1, consecutiveFastSelections: 1)
        )
        #expect(selection?.candidate.priority == .slow)
        #expect(selection?.candidate.identity.ecuSource == [2])
    }

    /// fast占有上限とECU公平上限の両方を適用します。
    @Test
    func schedulerAppliesFastAndECUFairnessLimits() {
        let now = Date(timeIntervalSince1970: 100)
        let candidates = [
            candidate(identity: identity(ecu: [1]), priority: .fast, eligible: 0, revisit: 200),
            candidate(identity: identity(ecu: [2]), priority: .normal, eligible: 0, revisit: 200)
        ]
        let selection = AdaptivePollingScheduler().selectNext(
            from: candidates,
            now: now,
            constraints: constraints,
            fairness: .init(lastECUSource: [1], consecutiveECUSelections: 1, consecutiveFastSelections: 1)
        )
        #expect(selection?.candidate.identity.ecuSource == [2])
        #expect(selection?.candidate.priority == .normal)
    }

    /// backoff上限超過、未要求on-demand、未確定制約を選びません。
    @Test
    func schedulerRejectsIneligibleAndUngatedCandidates() {
        let now = Date(timeIntervalSince1970: 100)
        let retry = AdaptivePollingScheduler.Candidate(
            identity: identity(ecu: [1]), priority: .probeBackoff,
            nextEligibleAt: .distantPast, latestRevisitAt: .distantPast,
            consecutiveFailures: 3, isDemanded: false
        )
        let demand = AdaptivePollingScheduler.Candidate(
            identity: identity(ecu: [2]), priority: .onDemand,
            nextEligibleAt: .distantPast, latestRevisitAt: .distantPast,
            consecutiveFailures: 0, isDemanded: false
        )
        let fairness = AdaptivePollingScheduler.FairnessState(lastECUSource: nil, consecutiveECUSelections: 0, consecutiveFastSelections: 0)
        #expect(AdaptivePollingScheduler().selectNext(from: [retry, demand], now: now, constraints: constraints, fairness: fairness) == nil)
        #expect(AdaptivePollingScheduler().selectNext(from: [candidate(identity: identity(ecu: [1]), priority: .normal, eligible: 0, revisit: 0)], now: now, constraints: nil, fairness: fairness) == nil)
    }

    /// Scan builderはstale Generation／attemptを拒否し、最終業務Evidenceを一件だけ作ります。
    @Test
    func scanBuilderRejectsStaleTokensAndFinalizesOnce() throws {
        let generation = ConnectionGeneration(value: 3)
        let first = UUID()
        let second = UUID()
        var builder = VehicleIdentificationScanBuilder(connectionGeneration: generation, obdConnectionID: UUID(), firstAttemptID: first)
        #expect(throws: VehicleIdentificationScanBuilder.Error.staleGeneration) {
            try builder.accept(rawCandidate("A"), generation: .init(value: 2), attemptID: first)
        }
        try builder.beginRetry(generation: generation, attemptID: second)
        #expect(throws: VehicleIdentificationScanBuilder.Error.staleAttempt) {
            try builder.accept(rawCandidate("A"), generation: generation, attemptID: first)
        }
        try builder.accept(rawCandidate("B"), generation: generation, attemptID: second)
        let evidence = try builder.finalize(generation: generation, attemptID: second, finishedAt: .now, isComplete: true)
        #expect(evidence.attemptIDs == [first, second])
        #expect(evidence.candidates.map(\.decodedCandidate) == ["B"])
        #expect(throws: VehicleIdentificationScanBuilder.Error.alreadyFinalized) {
            try builder.finalize(generation: generation, attemptID: second, finishedAt: .now, isComplete: true)
        }
    }

    /// 未確定VIN／国内車台番号規則はRawを保持してvalidへ昇格しません。
    @Test
    func blockedValidatorPreservesRawWithoutPromotion() {
        let candidate = rawCandidate("UNVERIFIED")
        let result = BlockedVehicleIdentifierValidator().validate(candidate)
        #expect(result.candidate.rawResponse == candidate.rawResponse)
        #expect(result.normalizationVersion == nil)
        #expect(result.status == .blocked)
    }

    /// 同kindの異なるvalid候補と別Vehicle一致をConflictにします。
    @Test
    func eligibilityDetectsIdentifierAndVehicleConflicts() {
        let evaluator = VehicleRegistrationEligibilityEvaluator()
        let a = validation("A")
        let b = validation("B")
        #expect(evaluator.evaluate(validations: [a, b], matches: [nil, nil]) == .conflict)
        #expect(evaluator.evaluate(validations: [a], matches: [nil]) == .newRegistration)
        #expect(evaluator.evaluate(validations: [.init(candidate: rawCandidate("X"), normalizationVersion: nil, status: .blocked)], matches: []) == .blocked)
    }

    /// テスト用PID Identityを作ります。数値は製品Catalogを表しません。
    private func identity(
        ecu: [UInt8],
        namespace: PIDSignalIdentity.Namespace = .standardOBD
    ) -> PIDSignalIdentity {
        PIDSignalIdentity(
            namespace: namespace,
            serviceOrMode: 1,
            parameter: 2,
            ecuSource: ecu,
            diagnosticProtocolKind: "protocol",
            decoderBundleVersion: "v1"
        )
    }

    /// Scheduler候補を固定時刻で作ります。
    private func candidate(
        identity: PIDSignalIdentity,
        priority: AdaptivePollingPriority,
        eligible: TimeInterval,
        revisit: TimeInterval
    ) -> AdaptivePollingScheduler.Candidate {
        .init(
            identity: identity,
            priority: priority,
            nextEligibleAt: Date(timeIntervalSince1970: eligible),
            latestRevisitAt: Date(timeIntervalSince1970: revisit),
            consecutiveFailures: 0,
            isDemanded: true
        )
    }

    /// Raw保持候補を作ります。
    private func rawCandidate(_ value: String) -> VehicleIdentifierCandidate {
        .init(kind: .vin, ecuSource: Data([1]), decodedCandidate: value, rawResponse: Data(value.utf8))
    }

    /// valid Validation結果を作ります。
    private func validation(_ value: String) -> VehicleIdentifierValidationResult {
        .init(candidate: rawCandidate(value), normalizationVersion: "test-v1", status: .valid(normalizedValue: value))
    }

    /// 小さな公平性テスト用制約です。製品既定値ではありません。
    private var constraints: AdaptivePollingScheduler.Constraints {
        .init(maximumConsecutiveSelectionsPerECU: 1, maximumConsecutiveFastSelections: 1, maximumRetryCount: 2)
    }
}
