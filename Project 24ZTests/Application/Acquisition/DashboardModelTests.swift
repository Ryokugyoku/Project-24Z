import Foundation
import Testing
@testable import Project_24Z

/// ダッシュボード主操作が設定状態から一貫導出されることを検証します。
@MainActor
struct DashboardModelTests {
    /// Primary未設定時に設定導線の文言、Label、Actionが一致します。
    @Test
    func missingPrimaryShowsConnectionSettingsAction() {
        let repository = InMemoryDefaultAdapterRepository()
        let scope = makeScope()
        let model = makeModel(repository: repository, scope: scope)

        model.load()

        #expect(model.state.primaryAction.title == "接続設定をする")
        #expect(model.state.primaryAction.accessibilityLabel == "接続設定をする")
        #expect(model.state.primaryAction.action == .openConnectionSettings)
        #expect(model.state.primaryAction.isEnabled)
    }

    /// Primary設定済み時にログ収集開始の文言、Label、Actionが一致します。
    @Test
    func configuredPrimaryShowsStartAction() throws {
        let repository = InMemoryDefaultAdapterRepository()
        let scope = makeScope()
        _ = try repository.setDefault(endpoint: .init(endpointDigest: Data(repeating: 8, count: 32), displayName: "Primary", transportKind: .bluetoothLE), role: .primaryOBD, in: scope, now: .now)
        let model = makeModel(repository: repository, scope: scope)

        model.load()

        #expect(model.state.primaryAction.title == "ログ収集を開始")
        #expect(model.state.primaryAction.accessibilityLabel == "ログ収集を開始")
        #expect(model.state.primaryAction.action == .startAcquisition)
        #expect(model.state.primaryAction.isEnabled)
    }

    /// 停止Actionは収集中かつ実停止能力がある場合だけ有効です。
    @Test
    func stopActionIsEnabledOnlyWhileAcquiringWithCapability() {
        let sessionID = UUID()
        let idle = DashboardModel.presentation(hasPrimary: true, acquisitionState: .idle, canStop: true)
        let unavailable = DashboardModel.presentation(hasPrimary: true, acquisitionState: .acquiringPID(sessionID: sessionID), canStop: false)
        let acquiring = DashboardModel.presentation(hasPrimary: true, acquisitionState: .acquiringPIDAndRawCAN(sessionID: sessionID), canStop: true)

        #expect(idle.primaryAction.action == .startAcquisition)
        #expect(unavailable.primaryAction.action == .none)
        #expect(!unavailable.primaryAction.isEnabled)
        #expect(acquiring.primaryAction.action == .stopAcquisition)
        #expect(acquiring.primaryAction.isEnabled)
    }

    /// 停止中は「停止中」を表示し、開始・停止のどちらも通知しません。
    @Test
    func stoppingDisablesStartAndStop() {
        let state = DashboardModel.presentation(hasPrimary: true, acquisitionState: .stopping(sessionID: UUID()), canStop: true)

        #expect(state.primaryAction.title == "停止中")
        #expect(state.primaryAction.action == .none)
        #expect(!state.primaryAction.isEnabled)
    }

    /// Dashboardの停止操作がApplication停止境界を一度だけ呼びます。
    @Test
    func stopActionCallsApplicationBoundaryOnce() async throws {
        let repository = InMemoryDefaultAdapterRepository()
        let scope = makeScope()
        _ = try repository.setDefault(endpoint: .init(endpointDigest: Data(repeating: 8, count: 32), displayName: "Primary", transportKind: .bluetoothLE), role: .primaryOBD, in: scope, now: .now)
        let recorder = AcquisitionStartEventRecorder()
        let starter = FakeAcquisitionSessionStarter(recorder: recorder)
        let startCoordinator = AcquisitionStartCoordinator(
            scope: scope,
            repository: repository,
            preflight: FakeAcquisitionStartPreflight(recorder: recorder, failure: nil),
            primaryPreparer: FakeAdapterConnectionPreparer(role: .primaryOBD, reference: .init(opaqueID: "primary"), recorder: recorder),
            secondaryPreparer: FakeAdapterConnectionPreparer(role: .secondaryRawCAN, reference: .init(opaqueID: "secondary"), recorder: recorder),
            sessionStarter: starter,
            activator: FakePreparedAcquisitionActivator(recorder: recorder)
        )
        let stopper = FakeAcquisitionStopCoordinator(result: .stopped(sessionID: starter.sessionID))
        let model = DashboardModel(repository: repository, scope: scope, coordinator: startCoordinator, stopCoordinator: stopper)
        model.load()
        await model.startAcquisition()

        await model.stopAcquisition()
        await model.stopAcquisition()

        #expect(await stopper.callCount == 1)
        #expect(model.state.acquisitionState == .stopped(sessionID: starter.sessionID))
    }

    /// Production未接続境界でCoordinatorを構成します。
    /// - Parameters:
    ///   - repository: 候補Repository。
    ///   - scope: 端末scope。
    /// - Returns: 検証対象Model。
    private func makeModel(repository: InMemoryDefaultAdapterRepository, scope: LocalDeviceScope) -> DashboardModel {
        let coordinator = AcquisitionStartCoordinator(scope: scope, repository: repository, preflight: UnavailableAcquisitionStartPreflight(), primaryPreparer: UnavailableAdapterConnectionPreparer(), secondaryPreparer: UnavailableAdapterConnectionPreparer(), sessionStarter: UnavailableAcquisitionSessionStarter(), activator: UnavailablePreparedAcquisitionActivator())
        return DashboardModel(repository: repository, scope: scope, coordinator: coordinator)
    }

    /// 固定Userの端末scopeを作ります。
    /// - Returns: テスト用scope。
    private func makeScope() -> LocalDeviceScope {
        .init(userScopeID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, localDeviceScopeID: UUID(), platform: .iOS)
    }
}
