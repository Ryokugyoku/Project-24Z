import Foundation
import Testing
@testable import Project_24Z

/// 正本停止順序と異常終端の非捏造を検証します。
@MainActor
struct AcquisitionStopCoordinatorTests {
    /// 正常停止は停止要求、PID、Raw CAN、callback、queue、終端、closeの順に一度ずつ進みます。
    @Test
    func cleanStopUsesCanonicalOrderOnce() async {
        let fixture = makeFixture()

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .stopped(sessionID: fixture.sessionID))
        #expect(fixture.persistence.requestCount == 1)
        #expect(fixture.persistence.completionCount == 1)
        #expect(fixture.recorder.events == ["request-stop", "stop-pid", "stop-raw-can", "invalidate-callbacks", "drain-and-finalize", "complete-stop", "close-transport"])
    }

    /// 保存失敗では正常終了せず、既存データを保持する復旧要境界を呼びます。
    @Test
    func persistenceFailureRequiresRecovery() async {
        let fixture = makeFixture()
        fixture.queue.failure = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .recoveryRequired(sessionID: fixture.sessionID, failure: .persistenceFailure))
        #expect(fixture.persistence.completionCount == 0)
        #expect(fixture.persistence.recoveryCount == 1)
        #expect(fixture.recorder.events.suffix(3) == ["drain-and-finalize", "require-recovery", "close-transport"])
    }

    /// 通信停止失敗でも両停止、callback失効、queue処理を試し、正常終了を捏造しません。
    @Test
    func communicationFailureStillInvalidatesAndDrains() async {
        let fixture = makeFixture()
        fixture.runtime.pidStopFails = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .recoveryRequired(sessionID: fixture.sessionID, failure: .communicationFailure))
        #expect(fixture.persistence.completionCount == 0)
        #expect(fixture.recorder.events.contains("stop-raw-can"))
        #expect(fixture.recorder.events.contains("invalidate-callbacks"))
        #expect(fixture.recorder.events.contains("drain-and-finalize"))
        #expect(fixture.recorder.events.last == "close-transport")
    }

    /// 停止要求transaction失敗後もRuntime、queue、Transportを必ず後始末します。
    @Test
    func stopRequestFailureStillCleansRuntimeAndQueue() async {
        let fixture = makeFixture()
        fixture.persistence.requestFails = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .recoveryRequired(sessionID: fixture.sessionID, failure: .stateUnknown))
        #expect(fixture.persistence.completionCount == 0)
        #expect(fixture.persistence.recoveryCount == 1)
        #expect(fixture.recorder.events == ["request-stop", "stop-pid", "stop-raw-can", "invalidate-callbacks", "drain-and-finalize", "require-recovery", "close-transport"])
    }

    /// 正常終端transaction失敗は復旧要へ進み、Transportを最後に閉じます。
    @Test
    func completionFailureRequiresRecoveryBeforeTransportClose() async {
        let fixture = makeFixture()
        fixture.persistence.completionFails = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .recoveryRequired(sessionID: fixture.sessionID, failure: .stateUnknown))
        #expect(fixture.persistence.recoveryCount == 1)
        #expect(fixture.recorder.events.suffix(3) == ["complete-stop", "require-recovery", "close-transport"])
    }

    /// 復旧要状態も確定不能なら正常終了を返さず、Transport後始末は維持します。
    @Test
    func recoveryFailureReturnsStateUnknownAndStillClosesTransport() async {
        let fixture = makeFixture()
        fixture.queue.failure = true
        fixture.persistence.recoveryFails = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .stateUnknown(sessionID: fixture.sessionID, failure: .persistenceFailure))
        #expect(fixture.persistence.completionCount == 0)
        #expect(fixture.recorder.events.last == "close-transport")
    }

    /// Raw CAN停止失敗を正常終了へ昇格しません。
    @Test
    func rawCANStopFailureRequiresRecovery() async {
        let fixture = makeFixture()
        fixture.runtime.rawStopFails = true

        let result = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(result == .recoveryRequired(sessionID: fixture.sessionID, failure: .communicationFailure))
        #expect(fixture.persistence.completionCount == 0)
        #expect(fixture.recorder.events.last == "close-transport")
    }

    /// 停止中の二重要求は状態不明を捏造せず、既存処理を重複実行しません。
    @Test
    func concurrentDuplicateStopIsRejectedWithoutRepeatingDependencies() async {
        let fixture = makeFixture()
        let suspension = AcquisitionStopSuspension()
        fixture.queue.suspension = suspension
        let first = Task { await fixture.coordinator.stop(sessionID: fixture.sessionID) }
        await suspension.waitUntilSuspended()

        let duplicate = await fixture.coordinator.stop(sessionID: fixture.sessionID)

        #expect(duplicate == .alreadyStopping(sessionID: fixture.sessionID))
        #expect(fixture.persistence.requestCount == 1)
        await suspension.resume()
        #expect(await first.value == .stopped(sessionID: fixture.sessionID))
        #expect(fixture.persistence.requestCount == 1)
    }

    /// 停止Fixtureを生成します。
    /// - Returns: Coordinatorと観測可能Fake群。
    private func makeFixture() -> Fixture {
        let recorder = AcquisitionStopEventRecorder()
        let persistence = FakeAcquisitionSessionStopPersistence(recorder: recorder)
        let runtime = FakeAcquisitionRuntimeStopper(recorder: recorder)
        let queue = FakeAcquisitionPersistenceQueueDrainer(recorder: recorder)
        let sessionID = UUID()
        let coordinator = AcquisitionStopCoordinator(persistence: persistence, runtime: runtime, queue: queue, deviceID: UUID(), now: { Date(timeIntervalSince1970: 1_800_000_100) })
        return .init(sessionID: sessionID, coordinator: coordinator, recorder: recorder, persistence: persistence, runtime: runtime, queue: queue)
    }

    /// 一テスト分の停止依存です。
    private struct Fixture {
        /// 対象Session IDです。
        let sessionID: UUID
        /// 検証対象Coordinatorです。
        let coordinator: AcquisitionStopCoordinator
        /// 順序Recorderです。
        let recorder: AcquisitionStopEventRecorder
        /// Session永続化Fakeです。
        let persistence: FakeAcquisitionSessionStopPersistence
        /// Runtime停止Fakeです。
        let runtime: FakeAcquisitionRuntimeStopper
        /// queue drain Fakeです。
        let queue: FakeAcquisitionPersistenceQueueDrainer
    }
}
