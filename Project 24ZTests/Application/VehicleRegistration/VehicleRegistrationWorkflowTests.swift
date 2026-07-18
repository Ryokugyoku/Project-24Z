import Foundation
import Testing
@testable import Project_24Z

/// 登録Applicationのtoken、重複、復元、結果不明、binding失敗を検証します。
@MainActor
struct VehicleRegistrationWorkflowTests {
    /// stale Generation／attemptの準備結果をRepositoryへ渡しません。
    @Test
    func staleGenerationAndAttemptAreRejectedBeforeQuery() throws {
        let dependencies = makeDependencies()
        let workflow = dependencies.workflow
        let generation = ConnectionGeneration(value: 2)
        let attempt = UUID()
        workflow.beginIdentification(generation: generation, attemptID: attempt)
        let context = makeContext(generation: generation, attempt: attempt)
        #expect(throws: VehicleRegistrationWorkflow.Error.staleGeneration) {
            try workflow.receivePreparedRegistration(context, generation: .init(value: 1), attemptID: attempt)
        }
        #expect(throws: VehicleRegistrationWorkflow.Error.staleAttempt) {
            try workflow.receivePreparedRegistration(context, generation: generation, attemptID: UUID())
        }
        #expect(dependencies.vehicle.registrationCallCount == 0)
    }

    /// 一致なしは新規登録し、登録transaction後に別bindingを行います。
    @Test
    func newRegistrationCommitsThenBindsSession() throws {
        let dependencies = makeDependencies()
        let context = beginReady(dependencies)
        let vehicle = activeVehicle(id: context.request.proposedVehicleID)
        dependencies.vehicle.registrationResults = [.success(.registered(vehicle))]
        let operation = UUID()
        try dependencies.workflow.confirmRegistration(operationID: operation, expectedRevision: dependencies.workflow.state.revision)
        guard case .registered(let registered, false, _, _) = dependencies.workflow.state else {
            Issue.record("binding済みregisteredが必要です。")
            return
        }
        #expect(registered.vehicleID == vehicle.vehicleID)
        #expect(dependencies.vehicle.registrationCallCount == 1)
        #expect(dependencies.binding.callCount == 1)
    }

    /// 同じoperationの二重Actionを拒否し、二重Vehicleを作りません。
    @Test
    func duplicateOperationIsRejected() throws {
        let dependencies = makeDependencies()
        let context = beginReady(dependencies)
        dependencies.vehicle.registrationResults = [.success(.registered(activeVehicle(id: context.request.proposedVehicleID)))]
        let operation = UUID()
        let revision = dependencies.workflow.state.revision
        try dependencies.workflow.confirmRegistration(operationID: operation, expectedRevision: revision)
        #expect(throws: VehicleRegistrationWorkflow.Error.duplicateOperation) {
            try dependencies.workflow.confirmRegistration(operationID: operation, expectedRevision: revision)
        }
        #expect(dependencies.vehicle.registrationCallCount == 1)
    }

    /// dispatch前取消しはRepository writeを呼ばず、commit後の遅い取消しは登録結果を削除しません。
    @Test
    func cancellationRespectsTransactionBoundary() throws {
        let before = makeDependencies()
        _ = beginReady(before)
        let cancelledOperation = UUID()
        before.workflow.cancel(operationID: cancelledOperation)
        #expect(throws: VehicleRegistrationWorkflow.Error.cancelled) {
            try before.workflow.confirmRegistration(operationID: cancelledOperation, expectedRevision: before.workflow.state.revision)
        }
        #expect(before.vehicle.registrationCallCount == 0)

        let after = makeDependencies()
        let context = beginReady(after)
        let vehicle = activeVehicle(id: context.request.proposedVehicleID)
        after.vehicle.registrationResults = [.success(.registered(vehicle))]
        let committedOperation = UUID()
        try after.workflow.confirmRegistration(operationID: committedOperation, expectedRevision: after.workflow.state.revision)
        after.workflow.cancel(operationID: committedOperation)
        guard case .registered(let persisted, false, _, _) = after.workflow.state else {
            Issue.record("commit後取消しで登録結果を削除してはいけません。")
            return
        }
        #expect(persisted.vehicleID == vehicle.vehicleID)
    }

    /// commit結果不明後は同一要求を再Queryして永続結果へ収束します。
    @Test
    func unknownTransactionResultConvergesByRetryQuery() throws {
        let dependencies = makeDependencies()
        let context = beginReady(dependencies)
        let vehicle = activeVehicle(id: context.request.proposedVehicleID)
        dependencies.vehicle.registrationResults = [
            .failure(.unavailable),
            .success(.registered(vehicle))
        ]
        let operation = UUID()
        #expect(throws: VehicleRegistrationWorkflow.Error.unavailable) {
            try dependencies.workflow.confirmRegistration(operationID: operation, expectedRevision: dependencies.workflow.state.revision)
        }
        guard case .transactionResultUnknown = dependencies.workflow.state else {
            Issue.record("結果不明Stateが必要です。")
            return
        }
        try dependencies.workflow.resolveUnknownResult(operationID: operation, expectedRevision: dependencies.workflow.state.revision)
        #expect(dependencies.vehicle.registrationCallCount == 2)
        #expect(dependencies.binding.callCount == 1)
    }

    /// archived一致はScan追加後も未登録で、明示復元後だけbindingします。
    @Test
    func archivedCandidateRequiresSeparateRestoreBeforeBinding() throws {
        let dependencies = makeDependencies()
        let generation = ConnectionGeneration(value: 1)
        let attempt = UUID()
        let context = makeContext(generation: generation, attempt: attempt)
        let archived = archivedVehicle()
        dependencies.vehicle.candidates[context.request.identifiers[0].lookupDigest] = archived
        dependencies.workflow.beginIdentification(generation: generation, attemptID: attempt)
        try dependencies.workflow.receivePreparedRegistration(context, generation: generation, attemptID: attempt)
        guard case .archivedDuplicate = dependencies.workflow.state else {
            Issue.record("archived候補が必要です。")
            return
        }
        dependencies.vehicle.registrationResults = [.success(.archivedRestoreRequired(archived))]
        try dependencies.workflow.confirmRegistration(operationID: UUID(), expectedRevision: dependencies.workflow.state.revision)
        #expect(dependencies.binding.callCount == 0)
        guard case .archivedRestoreRequired(_, let persisted, _) = dependencies.workflow.state else {
            Issue.record("復元待ちが必要です。")
            return
        }
        try dependencies.workflow.restoreArchivedVehicle(expectedLifecycleRevision: persisted.lifecycleRevision, expectedRevision: dependencies.workflow.state.revision)
        #expect(dependencies.vehicle.restoreCallCount == 1)
        #expect(dependencies.binding.callCount == 1)
    }

    /// stale lifecycle revisionは復元writeをdispatchしません。
    @Test
    func staleRestoreRevisionIsRejected() throws {
        let dependencies = makeDependencies()
        let state = try prepareArchivedRestoreRequired(dependencies)
        #expect(throws: VehicleRegistrationWorkflow.Error.invalidState) {
            try dependencies.workflow.restoreArchivedVehicle(expectedLifecycleRevision: state.lifecycleRevision + 1, expectedRevision: dependencies.workflow.state.revision)
        }
        #expect(dependencies.vehicle.restoreCallCount == 0)
        #expect(dependencies.binding.callCount == 0)
    }

    /// 復元失敗は追加済みScanと未割当Sessionを維持する復元待ちへ戻ります。
    @Test
    func restoreFailureKeepsRestoreRequiredAndUnassigned() throws {
        let dependencies = makeDependencies()
        let archived = try prepareArchivedRestoreRequired(dependencies)
        dependencies.vehicle.restoreError = .unavailable
        #expect(throws: VehicleRegistrationWorkflow.Error.unavailable) {
            try dependencies.workflow.restoreArchivedVehicle(expectedLifecycleRevision: archived.lifecycleRevision, expectedRevision: dependencies.workflow.state.revision)
        }
        guard case .archivedRestoreRequired = dependencies.workflow.state else {
            Issue.record("復元失敗後も復元待ちが必要です。")
            return
        }
        #expect(dependencies.binding.callCount == 0)
    }

    /// 登録成功後のbinding失敗はVehicleを維持してpendingを表現し、再試行できます。
    @Test
    func bindingFailureKeepsRegisteredVehicleAndCanRetry() throws {
        let dependencies = makeDependencies()
        let context = beginReady(dependencies)
        let vehicle = activeVehicle(id: context.request.proposedVehicleID)
        dependencies.vehicle.registrationResults = [.success(.registered(vehicle))]
        dependencies.vehicle.candidates[context.request.identifiers[0].lookupDigest] = vehicle
        dependencies.binding.error = .unavailable
        #expect(throws: VehicleRegistrationWorkflow.Error.unavailable) {
            try dependencies.workflow.confirmRegistration(operationID: UUID(), expectedRevision: dependencies.workflow.state.revision)
        }
        guard case .registered(let persisted, true, _, _) = dependencies.workflow.state else {
            Issue.record("binding pending registeredが必要です。")
            return
        }
        #expect(persisted.vehicleID == vehicle.vehicleID)
        dependencies.binding.error = nil
        try dependencies.workflow.retrySessionBinding(expectedRevision: dependencies.workflow.state.revision)
        #expect(dependencies.binding.callCount == 2)
    }

    /// binding直前の再archiveを候補再Queryで拒否します。
    @Test
    func rearchiveBeforeBindingIsRejected() throws {
        let dependencies = makeDependencies()
        let context = beginReady(dependencies)
        let active = activeVehicle(id: context.request.proposedVehicleID)
        dependencies.vehicle.registrationResults = [.success(.registered(active))]
        dependencies.vehicle.candidates[context.request.identifiers[0].lookupDigest] = archivedVehicle(id: active.vehicleID, revision: active.lifecycleRevision + 1)
        #expect(throws: VehicleRegistrationWorkflow.Error.conflict) {
            try dependencies.workflow.confirmRegistration(operationID: UUID(), expectedRevision: dependencies.workflow.state.revision)
        }
        #expect(dependencies.binding.callCount == 0)
        guard case .conflict = dependencies.workflow.state else {
            Issue.record("再archiveはConflictが必要です。")
            return
        }
    }

    /// 未割当Sessionを継続でき、明示終了時は既存Storage境界へ渡します。
    @Test
    func unassignedSessionCanContinueOrEnd() throws {
        let vehicle = FakeVehicleIdentityRepository()
        let binding = RecordingSessionVehicleBindingRepository()
        let session = RecordingUnassignedSessionRepository()
        let workflow = VehicleRegistrationWorkflow(
            vehicleRepository: vehicle,
            bindingRepository: binding,
            sessionRepository: session
        )
        workflow.beginIdentification(generation: .init(value: 1), attemptID: UUID())
        workflow.continueSessionUnassigned()
        guard case .idle = workflow.state else {
            Issue.record("未割当継続は登録せずidleへ戻る必要があります。")
            return
        }
        let sessionID = UUID()
        try workflow.endSessionUnassigned(
            sessionID: sessionID,
            expectedSessionRevision: 1,
            deviceID: UUID(),
            endedAt: .now
        )
        #expect(session.callCount == 1)
        #expect(session.sessionID == sessionID)
    }

    /// 依存Fake一式を作ります。
    private func makeDependencies() -> Dependencies {
        let vehicle = FakeVehicleIdentityRepository()
        let binding = RecordingSessionVehicleBindingRepository()
        return Dependencies(vehicle: vehicle, binding: binding, workflow: VehicleRegistrationWorkflow(vehicleRepository: vehicle, bindingRepository: binding))
    }

    /// 新規登録確認Stateまで進めます。
    private func beginReady(_ dependencies: Dependencies) -> VehicleRegistrationWorkflowContext {
        let generation = ConnectionGeneration(value: 1)
        let attempt = UUID()
        let context = makeContext(generation: generation, attempt: attempt)
        dependencies.workflow.beginIdentification(generation: generation, attemptID: attempt)
        try! dependencies.workflow.receivePreparedRegistration(context, generation: generation, attemptID: attempt)
        return context
    }

    /// archived Scan追加済み復元待ちを作ります。
    private func prepareArchivedRestoreRequired(_ dependencies: Dependencies) throws -> VehicleIdentity {
        let generation = ConnectionGeneration(value: 1)
        let attempt = UUID()
        let context = makeContext(generation: generation, attempt: attempt)
        let archived = archivedVehicle()
        dependencies.vehicle.candidates[context.request.identifiers[0].lookupDigest] = archived
        dependencies.workflow.beginIdentification(generation: generation, attemptID: attempt)
        try dependencies.workflow.receivePreparedRegistration(context, generation: generation, attemptID: attempt)
        dependencies.vehicle.registrationResults = [.success(.archivedRestoreRequired(archived))]
        try dependencies.workflow.confirmRegistration(operationID: UUID(), expectedRevision: dependencies.workflow.state.revision)
        return archived
    }

    /// Fixture要求へGeneration、attempt、Session tokenを追加します。
    private func makeContext(
        generation: ConnectionGeneration,
        attempt: UUID
    ) -> VehicleRegistrationWorkflowContext {
        VehicleRegistrationWorkflowContext(
            request: VehicleIdentityTestFixtures.registrationRequest(),
            connectionGeneration: generation,
            scanAttemptID: attempt,
            sessionID: UUID(),
            sessionRevision: 1
        )
    }

    /// active Fake車両を作ります。
    private func activeVehicle(id: UUID = UUID(), revision: Int = 1) -> VehicleIdentity {
        vehicle(id: id, lifecycle: .active, revision: revision)
    }

    /// archived Fake車両を作ります。
    private func archivedVehicle(id: UUID = UUID(), revision: Int = 1) -> VehicleIdentity {
        vehicle(id: id, lifecycle: .archived, revision: revision)
    }

    /// 指定LifecycleのFake車両を作ります。
    private func vehicle(id: UUID, lifecycle: VehicleIdentity.Lifecycle, revision: Int) -> VehicleIdentity {
        VehicleIdentity(
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            vehicleID: id,
            encryptedDisplayName: nil,
            lifecycle: lifecycle,
            recordRevision: revision,
            displayNameRevision: 0,
            lifecycleRevision: revision,
            archivedAt: lifecycle == .archived ? .now : nil,
            createdAt: VehicleIdentityTestFixtures.recordedAt,
            updatedAt: VehicleIdentityTestFixtures.recordedAt
        )
    }

    /// テスト依存をまとめるローカル値です。
    private struct Dependencies {
        /// 車両Fakeです。
        let vehicle: FakeVehicleIdentityRepository
        /// binding Fakeです。
        let binding: RecordingSessionVehicleBindingRepository
        /// 検証対象Workflowです。
        let workflow: VehicleRegistrationWorkflow
    }
}
