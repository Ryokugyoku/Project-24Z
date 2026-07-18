import Testing
@testable import Project_24Z

/// `VehicleRegistrationModel`の安全なProduction境界と全fixtureシナリオを検証します。
@MainActor
struct VehicleRegistrationModelTests {
    /// Production初期状態が安定したblocked／unavailableであることを検証します。
    @Test
    func productionInitialStateIsBlockedAndUnavailable() {
        let model = VehicleRegistrationModel()

        guard case .blocked(let display) = model.state else {
            Issue.record("Production初期状態はblockedである必要があります。")
            return
        }

        #expect(display.unavailableReason != nil)
        #expect(display.actionDisabledReason != nil)
        #expect(model.state.isRegistered == false)
    }

    /// Production blocked状態の未実装Actionが成功状態へ遷移しないことを検証します。
    @Test
    func unavailableProductionActionDoesNotRegisterVehicle() {
        let model = VehicleRegistrationModel()
        let initialState = model.state

        let result = model.perform(.retryIdentification(revision: model.state.revision))

        #expect(result == .rejectedInvalidState)
        #expect(model.state == initialState)
        #expect(model.state.isRegistered == false)
    }

    /// disconnectedが不透明Transport選択とAdapter選択だけを公開することを検証します。
    @Test
    func disconnectedAllowsOpaqueConnectionSelection() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.disconnected)
        guard case .disconnected(let disconnected) = model.state,
              let option = disconnected.transportOptions.first else {
            Issue.record("Transport候補を持つdisconnected fixtureが必要です。")
            return
        }

        let adapterResult = model.perform(
            .selectAdapter(
                identifier: option.adapterSelection,
                revision: disconnected.display.revision
            )
        )
        let connectionResult = model.perform(
            .startConnection(
                transportSelection: option.transportSelection,
                revision: disconnected.display.revision
            )
        )

        #expect(adapterResult == .rejectedUnavailable)
        #expect(connectionResult == .rejectedUnavailable)
        #expect(model.state.isRegistered == false)
    }

    /// adapterCheckingがAdapter選択を拒否し、取消可能境界だけを公開することを検証します。
    @Test
    func adapterCheckingDoesNotExposeAdapterSelection() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.adapterChecking)
        let selectionResult = model.perform(
            .selectAdapter(
                identifier: VehicleRegistrationPresentationIdentifier("test-adapter"),
                revision: model.state.revision
            )
        )
        let cancellationResult = model.perform(.cancelConnection(revision: model.state.revision))

        #expect(selectionResult == .rejectedInvalidState)
        #expect(cancellationResult == .rejectedUnavailable)
    }

    /// activeとarchivedの重複候補を明確に区別できることを検証します。
    @Test
    func duplicateCandidatesPreserveLifecycle() {
        guard case .duplicateCandidate(let active) = VehicleRegistrationPreviewFixtures.duplicateActive,
              case .duplicateCandidate(let archived) = VehicleRegistrationPreviewFixtures.duplicateArchived else {
            Issue.record("重複候補fixtureが不足しています。")
            return
        }

        #expect(active.lifecycle == .active)
        #expect(archived.lifecycle == .archived)
        #expect(active.display.maskedIdentifier != archived.display.maskedIdentifier)
    }

    /// archived復元待ちが登録済みでもSession binding可能でもないことを検証します。
    @Test
    func archivedRestoreRequiredIsNotRegisteredOrBindingEligible() {
        let state = VehicleRegistrationPreviewFixtures.archivedRestoreRequired

        #expect(state.isRegistered == false)
        #expect(state.allowsSessionBindingRetry == false)
        guard case .archivedRestoreRequired(let candidate) = state else {
            Issue.record("archivedRestoreRequired fixtureが必要です。")
            return
        }
        #expect(candidate.lifecycle == .archived)
    }

    /// archived復元中が通常登録済みでもSession binding可能でもないことを検証します。
    @Test
    func restoringArchivedVehicleIsNotRegisteredOrBindingEligible() {
        let state = VehicleRegistrationPreviewFixtures.restoringArchivedVehicle

        #expect(state.isRegistered == false)
        #expect(state.allowsSessionBindingRetry == false)
        guard case .restoringArchivedVehicle(let display) = state else {
            Issue.record("restoringArchivedVehicle fixtureが必要です。")
            return
        }
        #expect(display.progress != nil)
        #expect(display.isCancellationAvailable)
        #expect(display.sessionSummary.contains("未割当"))
    }

    /// stale lifecycle revisionの復元Actionを成功扱いしないことを検証します。
    @Test
    func staleLifecycleRevisionIsRejected() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.archivedRestoreRequired)
        guard case .archivedRestoreRequired(let candidate) = model.state,
              let identifier = candidate.display.actionIdentifier else {
            Issue.record("復元候補fixtureが必要です。")
            return
        }

        let result = model.perform(
            .confirmArchivedVehicleRestore(
                identifier: identifier,
                lifecycleRevision: candidate.lifecycleRevision + 1,
                revision: candidate.display.revision
            )
        )

        #expect(result == .rejectedStaleLifecycleRevision)
        #expect(model.state == VehicleRegistrationPreviewFixtures.archivedRestoreRequired)
        #expect(model.state.isRegistered == false)
    }

    /// 復元取消Actionを成功または登録済みとして扱わないことを検証します。
    @Test
    func restoreCancellationDoesNotRegisterVehicle() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.restoringArchivedVehicle)

        let result = model.perform(.cancelConnection(revision: model.state.revision))

        #expect(result == .rejectedUnavailable)
        #expect(model.state == VehicleRegistrationPreviewFixtures.restoringArchivedVehicle)
        #expect(VehicleRegistrationPreviewFixtures.restoreCancelled.isRegistered == false)
        #expect(VehicleRegistrationPreviewFixtures.restoreCancelled.display.title.contains("取り消"))
    }

    /// 復元revision競合と復元失敗を個別に表現し、成功扱いしないことを検証します。
    @Test
    func restoreConflictAndFailureRemainUnregistered() {
        let revisionConflict = VehicleRegistrationPreviewFixtures.restoreLifecycleRevisionConflict
        let restoreFailure = VehicleRegistrationPreviewFixtures.restoreFailed

        guard case .conflict = revisionConflict else {
            Issue.record("復元revision競合fixtureが必要です。")
            return
        }
        guard case .archivedRestoreRequired = restoreFailure else {
            Issue.record("復元失敗後の復元待ちfixtureが必要です。")
            return
        }

        #expect(revisionConflict.isRegistered == false)
        #expect(restoreFailure.isRegistered == false)
        #expect(revisionConflict.display.message.contains("revision"))
        #expect(restoreFailure.display.title.contains("復元できません"))
    }

    /// 登録済みとSession所属待ちを同時に表現できることを検証します。
    @Test
    func registeredStateCanRepresentBindingPending() {
        let state = VehicleRegistrationPreviewFixtures.sessionBindingPending

        #expect(state.isRegistered)
        #expect(state.allowsSessionBindingRetry)
        guard case .registered(let registered) = state else {
            Issue.record("registered fixtureが必要です。")
            return
        }
        #expect(registered.sessionBindingState == .pending)
    }

    /// 現在表示と一致しないpresentation revisionを拒否することを検証します。
    @Test
    func stalePresentationRevisionIsRejected() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.disconnected)
        guard case .disconnected(let disconnected) = model.state,
              let option = disconnected.transportOptions.first else {
            Issue.record("Transport候補を持つdisconnected fixtureが必要です。")
            return
        }
        let staleRevision = VehicleRegistrationPresentationRevision(model.state.revision.value + 1)

        let result = model.perform(
            .startConnection(
                transportSelection: option.transportSelection,
                revision: staleRevision
            )
        )

        #expect(result == .rejectedStalePresentation)
        #expect(model.state.isRegistered == false)
    }

    /// 別Actionを挟んでも同じoperationを再処理しないことを検証します。
    @Test
    func duplicateOperationIsRejectedAcrossInterveningAction() {
        let model = VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.disconnected)
        guard case .disconnected(let disconnected) = model.state,
              let option = disconnected.transportOptions.first else {
            Issue.record("Transport候補を持つdisconnected fixtureが必要です。")
            return
        }
        let adapterAction = VehicleRegistrationAction.selectAdapter(
            identifier: option.adapterSelection,
            revision: disconnected.display.revision
        )
        let connectionAction = VehicleRegistrationAction.startConnection(
            transportSelection: option.transportSelection,
            revision: disconnected.display.revision
        )

        let firstResult = model.perform(adapterAction)
        let interveningResult = model.perform(connectionAction)
        let repeatedResult = model.perform(adapterAction)

        #expect(firstResult == .rejectedUnavailable)
        #expect(interveningResult == .rejectedUnavailable)
        #expect(repeatedResult == .rejectedDuplicateAction)
        #expect(model.state.isRegistered == false)
    }

    /// 指定された各fixtureと復元シナリオが明示的に存在することを検証します。
    @Test
    func previewFixturesCoverRequiredStatesAndScenarios() {
        #expect(isDisconnected(VehicleRegistrationPreviewFixtures.disconnected))
        #expect(isConnecting(VehicleRegistrationPreviewFixtures.connecting))
        #expect(isAdapterChecking(VehicleRegistrationPreviewFixtures.adapterChecking))
        #expect(isIdentifying(VehicleRegistrationPreviewFixtures.identifying))
        #expect(isIdentificationUnavailable(VehicleRegistrationPreviewFixtures.identificationUnavailable))
        #expect(isDuplicate(VehicleRegistrationPreviewFixtures.duplicateActive, lifecycle: .active))
        #expect(isDuplicate(VehicleRegistrationPreviewFixtures.duplicateArchived, lifecycle: .archived))
        #expect(isArchivedRestoreRequired(VehicleRegistrationPreviewFixtures.archivedRestoreRequired))
        #expect(isRestoringArchivedVehicle(VehicleRegistrationPreviewFixtures.restoringArchivedVehicle))
        #expect(isArchivedRestoreRequired(VehicleRegistrationPreviewFixtures.restoreCancelled))
        #expect(isConflict(VehicleRegistrationPreviewFixtures.restoreLifecycleRevisionConflict))
        #expect(isArchivedRestoreRequired(VehicleRegistrationPreviewFixtures.restoreFailed))
        #expect(isConflict(VehicleRegistrationPreviewFixtures.conflict))
        #expect(isRegistrationReady(VehicleRegistrationPreviewFixtures.registrationReady))
        #expect(isRegistering(VehicleRegistrationPreviewFixtures.registering))
        #expect(isRegistered(VehicleRegistrationPreviewFixtures.registered, binding: .bound))
        #expect(isRegistered(VehicleRegistrationPreviewFixtures.sessionBindingPending, binding: .pending))
        #expect(isBlocked(VehicleRegistrationPreviewFixtures.blocked))
        #expect(isFailed(VehicleRegistrationPreviewFixtures.failed))
        #expect(VehicleRegistrationPreviewFixtures.allStates.contains(VehicleRegistrationPreviewFixtures.adapterChecking))
    }

    /// Production initializerがPreview fixtureのrevisionを使用しないことを検証します。
    @Test
    func productionInitializerDoesNotUsePreviewFixture() {
        let model = VehicleRegistrationModel()

        #expect(model.state.revision == VehicleRegistrationPresentationRevision(1))
        #expect(model.state.revision != VehicleRegistrationPreviewFixtures.blocked.revision)
    }

    /// 車両管理destinationを既存Session Modelから選択できることを検証します。
    @Test
    func vehicleManagementDestinationRemainsReachable() {
        let session = AppSessionModel()

        session.select(.vehicleManagement)

        #expect(session.selectedDestination == .vehicleManagement)
    }

    /// disconnected caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: disconnectedの場合は`true`。
    private func isDisconnected(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .disconnected = state { return true }
        return false
    }

    /// connecting caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: connectingの場合は`true`。
    private func isConnecting(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .connecting = state { return true }
        return false
    }

    /// adapterChecking caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: adapterCheckingの場合は`true`。
    private func isAdapterChecking(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .adapterChecking = state { return true }
        return false
    }

    /// identifying caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: identifyingの場合は`true`。
    private func isIdentifying(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .identifying = state { return true }
        return false
    }

    /// identificationUnavailable caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: identificationUnavailableの場合は`true`。
    private func isIdentificationUnavailable(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .identificationUnavailable = state { return true }
        return false
    }

    /// 指定lifecycleのduplicate候補かを返します。
    /// - Parameters:
    ///   - state: 検証対象State。
    ///   - lifecycle: 期待するlifecycle。
    /// - Returns: lifecycleが一致するduplicate候補の場合は`true`。
    private func isDuplicate(
        _ state: VehicleRegistrationPresentationState,
        lifecycle: VehicleRegistrationDuplicateCandidate.Lifecycle
    ) -> Bool {
        guard case .duplicateCandidate(let candidate) = state else { return false }
        return candidate.lifecycle == lifecycle
    }

    /// archivedRestoreRequired caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: archivedRestoreRequiredの場合は`true`。
    private func isArchivedRestoreRequired(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .archivedRestoreRequired = state { return true }
        return false
    }

    /// restoringArchivedVehicle caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: restoringArchivedVehicleの場合は`true`。
    private func isRestoringArchivedVehicle(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .restoringArchivedVehicle = state { return true }
        return false
    }

    /// conflict caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: conflictの場合は`true`。
    private func isConflict(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .conflict = state { return true }
        return false
    }

    /// registrationReady caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: registrationReadyの場合は`true`。
    private func isRegistrationReady(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .registrationReady = state { return true }
        return false
    }

    /// registering caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: registeringの場合は`true`。
    private func isRegistering(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .registering = state { return true }
        return false
    }

    /// 指定binding状態のregistered caseかを返します。
    /// - Parameters:
    ///   - state: 検証対象State。
    ///   - binding: 期待するSession binding状態。
    /// - Returns: binding状態が一致するregisteredの場合は`true`。
    private func isRegistered(
        _ state: VehicleRegistrationPresentationState,
        binding: VehicleRegistrationSessionBindingState
    ) -> Bool {
        guard case .registered(let registered) = state else { return false }
        return registered.sessionBindingState == binding
    }

    /// blocked caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: blockedの場合は`true`。
    private func isBlocked(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .blocked = state { return true }
        return false
    }

    /// failed caseかを返します。
    /// - Parameter state: 検証対象State。
    /// - Returns: failedの場合は`true`。
    private func isFailed(_ state: VehicleRegistrationPresentationState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
