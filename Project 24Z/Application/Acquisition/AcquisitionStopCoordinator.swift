import Foundation

/// 停止要求、通信停止、queue確定、Session終端の正本順序を所有します。
actor AcquisitionStopCoordinator: AcquisitionStopCoordinating {
    /// SessionとStream状態の永続化境界です。
    private let persistence: any AcquisitionSessionStopPersisting

    /// PID、Raw CAN、Transport Generationの停止境界です。
    private let runtime: any AcquisitionRuntimeStopping

    /// 保存queueとChunk確定境界です。
    private let queue: any AcquisitionPersistenceQueueDraining

    /// 更新端末IDです。
    private let deviceID: UUID

    /// 監査日時を返すclockです。
    private let now: @Sendable () -> Date

    /// 二重停止を拒否するprocess-local operation IDです。
    private var operationID: UUID?

    /// 停止Coordinatorを構成します。
    /// - Parameters:
    ///   - persistence: Session停止状態の正本境界。
    ///   - runtime: PID、Raw CAN、callback停止境界。
    ///   - queue: 保存queue確定境界。
    ///   - deviceID: 更新端末ID。
    ///   - now: 監査日時closure。
    init(
        persistence: any AcquisitionSessionStopPersisting,
        runtime: any AcquisitionRuntimeStopping,
        queue: any AcquisitionPersistenceQueueDraining,
        deviceID: UUID,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.runtime = runtime
        self.queue = queue
        self.deviceID = deviceID
        self.now = now
    }

    /// 停止を一度だけ実行し、全停止境界を試した後に終端状態を確定します。
    /// - Parameter sessionID: 収集中Session ID。
    /// - Returns: 正常終了、復旧要、または状態不明。
    func stop(sessionID: UUID) async -> AcquisitionStopResult {
        guard operationID == nil else {
            return .alreadyStopping(sessionID: sessionID)
        }
        let operation = UUID()
        operationID = operation
        defer { if operationID == operation { operationID = nil } }

        var context: AcquisitionStopContext?
        var failure: AcquisitionStopFailure?
        var recoveryReason = AcquisitionSession.EndReason.unknown
        do {
            context = try persistence.requestStop(sessionID: sessionID, requestedAt: now(), deviceID: deviceID)
        } catch {
            failure = .stateUnknown
        }

        do {
            try await runtime.stopPIDRequests(sessionID: sessionID)
        } catch {
            failure = failure ?? .communicationFailure
        }
        do {
            try await runtime.stopRawCANReception(sessionID: sessionID)
        } catch {
            failure = failure ?? .communicationFailure
        }

        await runtime.invalidateCallbacks(sessionID: sessionID)

        do {
            try await queue.drainAndFinalizeChunks(sessionID: sessionID)
        } catch {
            failure = .persistenceFailure
            recoveryReason = .writePipelineFailure
        }

        let result: AcquisitionStopResult
        if let failure {
            result = recover(sessionID: sessionID, failure: failure, reason: recoveryReason)
        } else if let context {
            do {
                try persistence.completeStop(context, endedAt: now(), deviceID: deviceID)
                result = .stopped(sessionID: sessionID)
            } catch {
                result = recover(sessionID: sessionID, failure: .stateUnknown, reason: .unknown)
            }
        } else {
            result = recover(sessionID: sessionID, failure: .stateUnknown, reason: .unknown)
        }
        await runtime.closeTransport(sessionID: sessionID)
        return result
    }

    /// 正常終了を推測せず、既存データを保持して復旧要状態を確定します。
    /// - Parameters:
    ///   - sessionID: 対象Session ID。
    ///   - failure: 利用者へ返す安定分類。
    ///   - reason: DBへ記録する異常終端理由。
    /// - Returns: 復旧要状態を確認できたかを含む結果。
    private func recover(
        sessionID: UUID,
        failure: AcquisitionStopFailure,
        reason: AcquisitionSession.EndReason
    ) -> AcquisitionStopResult {
        do {
            try persistence.requireRecovery(sessionID: sessionID, reason: reason, endedAt: now(), deviceID: deviceID)
            return .recoveryRequired(sessionID: sessionID, failure: failure)
        } catch {
            return .stateUnknown(sessionID: sessionID, failure: failure)
        }
    }
}
