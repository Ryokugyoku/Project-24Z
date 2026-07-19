import Foundation
@testable import Project_24Z

/// 保存queue drainとChunk確定を観測・失敗注入するFakeです。
final class FakeAcquisitionPersistenceQueueDrainer: AcquisitionPersistenceQueueDraining, @unchecked Sendable {
    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStopEventRecorder

    /// drainを失敗させるかを示します。
    var failure = false

    /// 並行停止テストでdrainを待機させる境界です。
    var suspension: AcquisitionStopSuspension?

    /// Fakeを構成します。
    /// - Parameter recorder: 共通Recorder。
    init(recorder: AcquisitionStopEventRecorder) { self.recorder = recorder }

    /// queue drainを記録します。
    /// - Parameter sessionID: 使用しないSession ID。
    /// - Throws: `failure`なら保存失敗。
    func drainAndFinalizeChunks(sessionID: UUID) async throws {
        recorder.append("drain-and-finalize")
        if let suspension {
            await suspension.suspend()
        }
        if failure { throw AcquisitionStopFailure.persistenceFailure }
    }
}
