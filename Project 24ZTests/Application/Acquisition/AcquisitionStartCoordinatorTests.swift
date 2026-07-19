import Foundation
import Testing
@testable import Project_24Z

/// Session commit前後とSecondary縮退判断の開始順序を検証します。
@MainActor
struct AcquisitionStartCoordinatorTests {
    /// Primary／Secondary準備後にSession commitし、その後だけ取得を開始します。
    @Test
    func commitPrecedesDualStreamActivation() async throws {
        let fixture = try makeFixture(includeSecondary: true)

        await fixture.coordinator.start()

        #expect(fixture.recorder.events == ["preflight", "prepare-primary", "prepare-secondary", "commit", "activate"])
        #expect(fixture.starter.includedSecondary == true)
        #expect(fixture.coordinator.state == .acquiringPIDAndRawCAN(sessionID: fixture.starter.sessionID))
    }

    /// Secondary失敗では利用者確認までSessionを作らず、PIDのみ選択後に一Streamで開始します。
    @Test
    func secondaryFailureRequiresExplicitPIDOnlyConfirmation() async throws {
        let fixture = try makeFixture(includeSecondary: true)
        fixture.secondary.failure = .rawCANReceiveOnlyUnverified

        await fixture.coordinator.start()
        #expect(fixture.starter.callCount == 0)
        #expect(fixture.coordinator.state == .awaitingPIDOnlyConfirmation(failure: .rawCANReceiveOnlyUnverified))

        await fixture.coordinator.confirmPIDOnlyStart()
        #expect(fixture.starter.callCount == 1)
        #expect(fixture.starter.includedSecondary == false)
        #expect(fixture.coordinator.state == .acquiringPID(sessionID: fixture.starter.sessionID))
    }

    /// Secondary失敗後のキャンセルが全Transportを閉じ、Sessionを作らないことを検証します。
    @Test
    func cancellingSecondaryDecisionCreatesNoSession() async throws {
        let fixture = try makeFixture(includeSecondary: true)
        fixture.secondary.failure = .transportUnavailable
        await fixture.coordinator.start()

        await fixture.coordinator.cancel()

        #expect(fixture.starter.callCount == 0)
        #expect(fixture.primary.closeCount == 1)
        #expect(fixture.secondary.closeCount == 1)
        #expect(fixture.coordinator.state == .cancelled)
    }

    /// 同一物理Adapterと確認された場合に両Stream Sessionを作らないことを検証します。
    @Test
    func samePhysicalAdapterCannotStartDualStreams() async throws {
        let recorder = AcquisitionStartEventRecorder()
        let repository = InMemoryDefaultAdapterRepository()
        let scope = makeScope()
        try addCandidates(repository: repository, scope: scope, includeSecondary: true)
        let sameReference = AdapterReference(opaqueID: "same")
        let primary = FakeAdapterConnectionPreparer(role: .primaryOBD, reference: sameReference, recorder: recorder)
        let secondary = FakeAdapterConnectionPreparer(role: .secondaryRawCAN, reference: sameReference, recorder: recorder)
        let starter = FakeAcquisitionSessionStarter(recorder: recorder)
        let coordinator = AcquisitionStartCoordinator(scope: scope, repository: repository, preflight: FakeAcquisitionStartPreflight(recorder: recorder, failure: nil), primaryPreparer: primary, secondaryPreparer: secondary, sessionStarter: starter, activator: FakePreparedAcquisitionActivator(recorder: recorder))

        await coordinator.start()

        #expect(coordinator.state == .awaitingPIDOnlyConfirmation(failure: .adaptersNotDistinct))
        #expect(starter.callCount == 0)
    }

    /// テストに必要な全境界を構成します。
    /// - Parameter includeSecondary: Secondary候補を保存するか。
    /// - Returns: Coordinatorと観測可能Fake群。
    private func makeFixture(includeSecondary: Bool) throws -> Fixture {
        let recorder = AcquisitionStartEventRecorder()
        let repository = InMemoryDefaultAdapterRepository()
        let scope = makeScope()
        try addCandidates(repository: repository, scope: scope, includeSecondary: includeSecondary)
        let primary = FakeAdapterConnectionPreparer(role: .primaryOBD, reference: .init(opaqueID: "primary"), recorder: recorder)
        let secondary = FakeAdapterConnectionPreparer(role: .secondaryRawCAN, reference: .init(opaqueID: "secondary"), recorder: recorder)
        let starter = FakeAcquisitionSessionStarter(recorder: recorder)
        let activator = FakePreparedAcquisitionActivator(recorder: recorder)
        let coordinator = AcquisitionStartCoordinator(scope: scope, repository: repository, preflight: FakeAcquisitionStartPreflight(recorder: recorder, failure: nil), primaryPreparer: primary, secondaryPreparer: secondary, sessionStarter: starter, activator: activator)
        return .init(coordinator: coordinator, recorder: recorder, primary: primary, secondary: secondary, starter: starter, activator: activator)
    }

    /// Repositoryへ役割別候補を保存します。
    /// - Parameters:
    ///   - repository: In-memory Repository。
    ///   - scope: 保存scope。
    ///   - includeSecondary: Secondaryも保存するか。
    private func addCandidates(repository: InMemoryDefaultAdapterRepository, scope: LocalDeviceScope, includeSecondary: Bool) throws {
        _ = try repository.setDefault(endpoint: .init(endpointDigest: Data(repeating: 1, count: 32), displayName: "Primary", transportKind: .bluetoothLE), role: .primaryOBD, in: scope, now: .now)
        if includeSecondary {
            _ = try repository.setDefault(endpoint: .init(endpointDigest: Data(repeating: 2, count: 32), displayName: "Secondary", transportKind: .bluetoothLE), role: .secondaryRawCAN, in: scope, now: .now)
        }
    }

    /// 固定Userの端末scopeを作ります。
    /// - Returns: テスト用scope。
    private func makeScope() -> LocalDeviceScope {
        .init(userScopeID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, localDeviceScopeID: UUID(), platform: .iOS)
    }

    /// 一テストのCoordinatorとFake群です。
    private struct Fixture {
        /// 検証対象Coordinatorです。
        let coordinator: AcquisitionStartCoordinator
        /// 順序Recorderです。
        let recorder: AcquisitionStartEventRecorder
        /// Primary Fakeです。
        let primary: FakeAdapterConnectionPreparer
        /// Secondary Fakeです。
        let secondary: FakeAdapterConnectionPreparer
        /// Session Starter Fakeです。
        let starter: FakeAcquisitionSessionStarter
        /// Activator Fakeです。
        let activator: FakePreparedAcquisitionActivator
    }
}
