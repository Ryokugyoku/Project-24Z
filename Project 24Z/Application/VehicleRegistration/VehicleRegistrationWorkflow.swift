import Foundation

/// 識別終端から重複照合、登録、復元、Session所属を順序付けるApplication境界です。
@MainActor
final class VehicleRegistrationWorkflow {
    /// staleまたは不正Actionの拒否理由です。
    enum Error: Swift.Error, Equatable {
        case staleGeneration
        case staleAttempt
        case staleRevision
        case staleOperation
        case invalidState
        case duplicateOperation
        case cancelled
        case conflict
        case unavailable
    }

    /// Platformへ公開できる現在の論理状態です。
    private(set) var state: VehicleRegistrationWorkflowState = .idle(revision: 0)

    private let vehicleRepository: any VehicleIdentityRepository
    private let bindingRepository: any SessionVehicleBindingRepository
    private let sessionRepository: (any UnassignedSessionRepository)?
    private var currentGeneration: ConnectionGeneration?
    private var currentAttemptID: UUID?
    private var processedOperations: Set<UUID> = []
    private var cancelledOperations: Set<UUID> = []
    private var revision: UInt64 = 0

    /// Repository境界を注入します。
    /// - Parameters:
    ///   - vehicleRepository: 車両登録transaction境界。
    ///   - bindingRepository: 分離されたSession binding transaction境界。
    ///   - sessionRepository: 未割当Session終了境界。終了Actionを使わない構成ではnil。
    init(
        vehicleRepository: any VehicleIdentityRepository,
        bindingRepository: any SessionVehicleBindingRepository,
        sessionRepository: (any UnassignedSessionRepository)? = nil
    ) {
        self.vehicleRepository = vehicleRepository
        self.bindingRepository = bindingRepository
        self.sessionRepository = sessionRepository
    }

    /// 新しい接続Generationと識別attemptをcurrentにします。
    /// - Parameters:
    ///   - generation: Runtime接続Generation。
    ///   - attemptID: Scan attempt UUID。
    func beginIdentification(generation: ConnectionGeneration, attemptID: UUID) {
        currentGeneration = generation
        currentAttemptID = attemptID
        state = .identifying(generation: generation, attemptID: attemptID, revision: nextRevision())
    }

    /// 暗号準備済み終端Snapshotを照合し、登録可否状態へ進めます。
    /// - Parameters:
    ///   - context: 登録とSessionを接続する不変Context。
    ///   - generation: 結果生成時のGeneration。
    ///   - attemptID: 結果生成時のattempt UUID。
    /// - Throws: stale token、無効Snapshot、Repository失敗。
    func receivePreparedRegistration(
        _ context: VehicleRegistrationWorkflowContext,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) throws {
        guard currentGeneration == generation else { throw Error.staleGeneration }
        guard currentAttemptID == attemptID else { throw Error.staleAttempt }
        guard context.connectionGeneration == generation,
              context.scanAttemptID == attemptID,
              context.request.scan.status == .completed,
              context.request.scan.identityValidationState == .valid,
              !context.request.identifiers.isEmpty else {
            state = .blocked(revision: nextRevision())
            throw Error.invalidState
        }
        do {
            let candidates = try context.request.identifiers.map {
                try vehicleRepository.findCandidate(kind: $0.kind, lookupDigest: $0.lookupDigest)
            }
            let matched = candidates.compactMap { $0 }
            let ids = Set(matched.map(\.vehicleID))
            guard ids.count <= 1,
                  matched.isEmpty || matched.count == candidates.count else {
                state = .conflict(revision: nextRevision())
                throw Error.conflict
            }
            guard let candidate = matched.first else {
                state = .registrationReady(context, revision: nextRevision())
                return
            }
            let guarded = replacingCandidate(in: context, with: candidate)
            if candidate.lifecycle == .active {
                state = .activeDuplicate(guarded, candidate, revision: nextRevision())
            } else {
                state = .archivedDuplicate(guarded, candidate, revision: nextRevision())
            }
        } catch let error as Error {
            throw error
        } catch let error as VehiclePersistenceError where error == .conflict || error == .idempotencyConflict {
            state = .conflict(revision: nextRevision())
            throw Error.conflict
        } catch {
            state = .blocked(revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// 新規または確認済み既存候補の登録transactionを一度だけdispatchします。
    /// - Parameters:
    ///   - operationID: process内二重ActionをcoalesceするUUID。
    ///   - expectedRevision: Action生成時のpresentation revision。
    /// - Throws: stale、取消し、競合、利用不能。
    func confirmRegistration(operationID: UUID, expectedRevision: UInt64) throws {
        guard !processedOperations.contains(operationID) else { throw Error.duplicateOperation }
        guard !cancelledOperations.contains(operationID) else { throw Error.cancelled }
        guard expectedRevision == state.revision else { throw Error.staleRevision }
        let context: VehicleRegistrationWorkflowContext
        switch state {
        case .registrationReady(let value, _), .activeDuplicate(let value, _, _), .archivedDuplicate(let value, _, _):
            context = value
        default:
            throw Error.invalidState
        }
        try verifyCurrent(context)
        processedOperations.insert(operationID)
        state = .registering(operationID: operationID, revision: nextRevision())
        guard !cancelledOperations.contains(operationID) else { throw Error.cancelled }
        do {
            try apply(vehicleRepository.register(context.request), context: context)
        } catch let error as Error {
            throw error
        } catch VehiclePersistenceError.unavailable {
            state = .transactionResultUnknown(context, operationID: operationID, revision: nextRevision())
            throw Error.unavailable
        } catch VehiclePersistenceError.conflict, VehiclePersistenceError.idempotencyConflict {
            state = .conflict(revision: nextRevision())
            throw Error.conflict
        } catch {
            state = .failed(revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// commit結果不明時に同一Identifier＋connection SnapshotをRepositoryの再Queryへ収束させます。
    /// - Parameters:
    ///   - operationID: 元の登録operation UUID。
    ///   - expectedRevision: transaction結果不明Stateのrevision。
    /// - Throws: stale operation、競合、利用不能。
    func resolveUnknownResult(operationID: UUID, expectedRevision: UInt64) throws {
        guard expectedRevision == state.revision else { throw Error.staleRevision }
        guard case .transactionResultUnknown(let context, let currentOperationID, _) = state,
              currentOperationID == operationID else {
            throw Error.staleOperation
        }
        do {
            try apply(vehicleRepository.register(context.request), context: context)
        } catch let error as Error {
            throw error
        } catch VehiclePersistenceError.conflict, VehiclePersistenceError.idempotencyConflict {
            state = .conflict(revision: nextRevision())
            throw Error.conflict
        } catch {
            state = .transactionResultUnknown(context, operationID: operationID, revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// archived Scan追加後に期待Revisionで明示復元します。
    /// - Parameters:
    ///   - expectedLifecycleRevision: UIが確認したLifecycle Revision。
    ///   - expectedRevision: presentation revision。
    /// - Throws: stale revision、取消し、Repository競合。
    func restoreArchivedVehicle(
        expectedLifecycleRevision: Int,
        expectedRevision: UInt64
    ) throws {
        guard expectedRevision == state.revision else { throw Error.staleRevision }
        guard case .archivedRestoreRequired(let context, let vehicle, _) = state,
              vehicle.lifecycleRevision == expectedLifecycleRevision,
              let evidence = context.request.identifiers.first else {
            throw Error.invalidState
        }
        do {
            let restored = try vehicleRepository.restoreArchivedVehicle(
                vehicleID: vehicle.vehicleID,
                expectedLifecycleRevision: expectedLifecycleRevision,
                identifierKind: evidence.kind,
                lookupDigest: evidence.lookupDigest,
                deviceID: context.request.deviceID,
                updatedAt: context.request.recordedAt
            )
            try bind(restored, context: context)
        } catch let error as Error {
            throw error
        } catch VehiclePersistenceError.conflict {
            state = .conflict(revision: nextRevision())
            throw Error.conflict
        } catch {
            state = .archivedRestoreRequired(context, vehicle, revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// 登録済みだが未割当のSession所属を同じContextで再試行します。
    /// - Parameter expectedRevision: binding pending Stateのrevision。
    /// - Throws: stale、再archive、Session競合。
    func retrySessionBinding(expectedRevision: UInt64) throws {
        guard expectedRevision == state.revision else { throw Error.staleRevision }
        guard case .registered(let vehicle, true, let context, _) = state else { throw Error.invalidState }
        try bind(vehicle, context: context)
    }

    /// write dispatch前の同一operationを取り消します。
    /// - Parameter operationID: 取消対象operation UUID。
    func cancel(operationID: UUID) {
        cancelledOperations.insert(operationID)
    }

    /// 未割当Sessionを削除せず、登録フローだけを閉じます。
    func continueSessionUnassigned() {
        currentGeneration = nil
        currentAttemptID = nil
        state = .idle(revision: nextRevision())
    }

    /// 車両未割当のまま既存Storage境界でSessionを終了します。
    /// - Parameters:
    ///   - sessionID: 未割当Session UUID。
    ///   - expectedSessionRevision: 期待Session Revision。
    ///   - deviceID: 更新端末UUID。
    ///   - endedAt: 終端日時。
    /// - Throws: Repository未接続、stale Session、保存失敗。
    func endSessionUnassigned(
        sessionID: UUID,
        expectedSessionRevision: Int,
        deviceID: UUID,
        endedAt: Date
    ) throws {
        guard let sessionRepository else {
            state = .blocked(revision: nextRevision())
            throw Error.unavailable
        }
        do {
            try sessionRepository.finishSession(
                sessionID: sessionID,
                expectedSessionRevision: expectedSessionRevision,
                reason: .userStop,
                endedAt: endedAt,
                deviceID: deviceID
            )
            currentGeneration = nil
            currentAttemptID = nil
            state = .idle(revision: nextRevision())
        } catch {
            state = .blocked(revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// 登録結果を状態へ適用し、activeなら分離されたbindingを試行します。
    /// - Parameters:
    ///   - result: Repository commit結果。
    ///   - context: 同一登録Context。
    /// - Throws: binding境界が返す競合または利用不能。
    private func apply(
        _ result: VehicleRegistrationResult,
        context: VehicleRegistrationWorkflowContext
    ) throws {
        switch result {
        case .registered(let vehicle):
            try bind(vehicle, context: context)
        case .archivedRestoreRequired(let vehicle):
            state = .archivedRestoreRequired(context, vehicle, revision: nextRevision())
        }
    }

    /// binding直前に全Identifierが同じactive車両へ一意一致することを再確認します。
    /// - Parameters:
    ///   - vehicle: 登録または復元済みactive車両。
    ///   - context: SessionとIdentifier根拠。
    /// - Throws: 再archive、照合変化、Session競合。
    private func bind(
        _ vehicle: VehicleIdentity,
        context: VehicleRegistrationWorkflowContext
    ) throws {
        guard vehicle.lifecycle == .active else {
            state = .archivedRestoreRequired(context, vehicle, revision: nextRevision())
            throw Error.conflict
        }
        do {
            for evidence in context.request.identifiers {
                let candidate = try vehicleRepository.findCandidate(kind: evidence.kind, lookupDigest: evidence.lookupDigest)
                guard candidate?.vehicleID == vehicle.vehicleID,
                      candidate?.lifecycle == .active,
                      candidate?.lifecycleRevision == vehicle.lifecycleRevision else {
                    state = .conflict(revision: nextRevision())
                    throw Error.conflict
                }
            }
            try bindingRepository.bind(
                sessionID: context.sessionID,
                vehicleID: vehicle.vehicleID,
                expectedSessionRevision: context.sessionRevision,
                expectedVehicleLifecycleRevision: vehicle.lifecycleRevision
            )
            state = .registered(vehicle, bindingPending: false, context: context, revision: nextRevision())
        } catch let error as Error {
            throw error
        } catch {
            state = .registered(vehicle, bindingPending: true, context: context, revision: nextRevision())
            throw Error.unavailable
        }
    }

    /// Contextがcurrent generation／attemptに属することを再確認します。
    /// - Parameter context: dispatch直前のContext。
    /// - Throws: stale tokenならRepositoryを呼びません。
    private func verifyCurrent(_ context: VehicleRegistrationWorkflowContext) throws {
        guard currentGeneration == context.connectionGeneration else { throw Error.staleGeneration }
        guard currentAttemptID == context.scanAttemptID else { throw Error.staleAttempt }
    }

    /// 既存候補のUUIDとLifecycle Revisionを不変要求へ固定します。
    /// - Parameters:
    ///   - context: 元Context。
    ///   - vehicle: 一意な既存候補。
    /// - Returns: transaction再確認値を持つContext。
    private func replacingCandidate(
        in context: VehicleRegistrationWorkflowContext,
        with vehicle: VehicleIdentity
    ) -> VehicleRegistrationWorkflowContext {
        let request = context.request
        return VehicleRegistrationWorkflowContext(
            request: VehicleRegistrationRequest(
                proposedVehicleID: request.proposedVehicleID,
                encryptedDisplayName: request.encryptedDisplayName,
                identifiers: request.identifiers,
                scan: request.scan,
                deviceID: request.deviceID,
                recordedAt: request.recordedAt,
                expectedCandidateVehicleID: vehicle.vehicleID,
                expectedCandidateLifecycleRevision: vehicle.lifecycleRevision
            ),
            connectionGeneration: context.connectionGeneration,
            scanAttemptID: context.scanAttemptID,
            sessionID: context.sessionID,
            sessionRevision: context.sessionRevision
        )
    }

    /// presentation revisionを単調増加させます。
    /// - Returns: 更新後revision。
    private func nextRevision() -> UInt64 {
        revision += 1
        return revision
    }
}
