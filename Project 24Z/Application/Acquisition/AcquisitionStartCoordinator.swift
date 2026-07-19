import Foundation

/// Primary／Secondary準備とSession commit順序を一箇所で保証します。
@MainActor
final class AcquisitionStartCoordinator {
    /// 現在の開始状態です。
    private(set) var state: AcquisitionStartState = .idle

    /// 端末別候補を読むRepositoryです。
    private let repository: any DefaultAdapterRepository

    /// Sessionを作らない開始前検査です。
    private let preflight: any AcquisitionStartPreflightChecking

    /// Primary専用準備境界です。
    private let primaryPreparer: any AdapterConnectionPreparing

    /// Secondary専用準備境界です。
    private let secondaryPreparer: any AdapterConnectionPreparing

    /// BEGIN IMMEDIATE相当で開始目録をcommitする境界です。
    private let sessionStarter: any AcquisitionSessionStarting

    /// commit後だけ取得を開始する境界です。
    private let activator: any PreparedAcquisitionActivating

    /// 今回の端末境界です。
    private let scope: LocalDeviceScope

    /// 監査日時を返すclockです。
    private let now: () -> Date

    /// stale完了を拒否するprocess-local operation IDです。
    private var operationID: UUID?

    /// 次に発行するConnection Generationです。
    private var generationValue: UInt64 = 0

    /// Secondary失敗後の利用者判断まで保持するPrimary接続です。
    private var pendingPrimary: PreparedAdapterConnection?

    /// 開始Coordinatorを構成します。
    /// - Parameters:
    ///   - scope: 認証済みUser・端末境界。
    ///   - repository: 既定候補Repository。
    ///   - preflight: DB、容量、鍵の開始前検査。
    ///   - primaryPreparer: Primary専用準備境界。
    ///   - secondaryPreparer: Secondary専用準備境界。
    ///   - sessionStarter: Session transaction境界。
    ///   - activator: commit後の取得開始境界。
    ///   - now: 監査日時closure。
    init(
        scope: LocalDeviceScope,
        repository: any DefaultAdapterRepository,
        preflight: any AcquisitionStartPreflightChecking,
        primaryPreparer: any AdapterConnectionPreparing,
        secondaryPreparer: any AdapterConnectionPreparing,
        sessionStarter: any AcquisitionSessionStarting,
        activator: any PreparedAcquisitionActivating,
        now: @escaping () -> Date = Date.init
    ) {
        self.scope = scope
        self.repository = repository
        self.preflight = preflight
        self.primaryPreparer = primaryPreparer
        self.secondaryPreparer = secondaryPreparer
        self.sessionStarter = sessionStarter
        self.activator = activator
        self.now = now
    }

    /// 二重開始を拒否し、新Generationで準備を開始します。
    func start() async {
        guard operationID == nil else { return }
        let operation = UUID()
        operationID = operation
        pendingPrimary = nil

        do {
            let candidates = try repository.activeCandidates(in: scope)
            guard let primaryCandidate = candidates[.primaryOBD] else {
                throw AcquisitionStartFailure.preflightBlocked
            }
            state = .preflight
            try await preflight.checkStartEligibility()
            try ensureCurrent(operation)

            state = .preparingPrimary
            let primary = try await primaryPreparer.prepare(
                candidate: primaryCandidate,
                binding: try repository.verifiedBinding(candidateID: primaryCandidate.candidateID, in: scope),
                generation: nextGeneration()
            )
            try ensureCurrent(operation)

            guard let secondaryCandidate = candidates[.secondaryRawCAN] else {
                try await commitAndActivate(primary: primary, secondary: nil, operation: operation)
                return
            }

            state = .preparingSecondary
            do {
                let secondary = try await secondaryPreparer.prepare(
                    candidate: secondaryCandidate,
                    binding: try repository.verifiedBinding(candidateID: secondaryCandidate.candidateID, in: scope),
                    generation: nextGeneration()
                )
                try ensureCurrent(operation)
                guard primary.adapterReference != secondary.adapterReference else {
                    throw AcquisitionStartFailure.adaptersNotDistinct
                }
                try await commitAndActivate(primary: primary, secondary: secondary, operation: operation)
            } catch {
                try ensureCurrent(operation)
                pendingPrimary = primary
                state = .awaitingPIDOnlyConfirmation(failure: classify(error))
            }
        } catch {
            await failBeforeSession(error, operation: operation)
        }
    }

    /// Secondary失敗後、利用者確認によりPID Streamだけで開始します。
    func confirmPIDOnlyStart() async {
        guard case .awaitingPIDOnlyConfirmation = state,
              let operation = operationID,
              let primary = pendingPrimary else { return }
        pendingPrimary = nil
        await secondaryPreparer.close()
        do {
            try await commitAndActivate(primary: primary, secondary: nil, operation: operation)
        } catch {
            await failBeforeSession(error, operation: operation)
        }
    }

    /// 開始処理または縮退判断を取消し、Session commit前のTransportを閉じます。
    func cancel() async {
        guard operationID != nil else { return }
        operationID = nil
        pendingPrimary = nil
        await primaryPreparer.close()
        await secondaryPreparer.close()
        state = .cancelled
    }

    /// Stream集合確定後にcommitし、その成功後だけ取得を開始します。
    /// - Parameters:
    ///   - primary: 準備済みPrimary。
    ///   - secondary: 準備済みSecondary。PIDのみなら`nil`。
    ///   - operation: stale拒否用ID。
    /// - Throws: commit前のstale／取消し、またはcommit失敗。
    private func commitAndActivate(
        primary: PreparedAdapterConnection,
        secondary: PreparedAdapterConnection?,
        operation: UUID
    ) async throws {
        try ensureCurrent(operation)
        state = .committingSession
        let sessionID: UUID
        do {
            sessionID = try await sessionStarter.startSession(in: scope, primary: primary, secondary: secondary, startedAt: now())
        } catch {
            throw AcquisitionStartFailure.sessionCommitFailed
        }
        do {
            try ensureCurrent(operation)
            try await activator.activate(sessionID: sessionID, primary: primary, secondary: secondary)
            try ensureCurrent(operation)
            state = secondary == nil ? .acquiringPID(sessionID: sessionID) : .acquiringPIDAndRawCAN(sessionID: sessionID)
            operationID = nil
        } catch {
            operationID = nil
            state = .failedAfterSession(sessionID: sessionID, failure: .acquisitionFailedAfterCommit)
        }
    }

    /// Session作成前の失敗を閉じ、空Sessionを作りません。
    /// - Parameters:
    ///   - error: 発生したError。
    ///   - operation: 対象operation ID。
    private func failBeforeSession(_ error: Error, operation: UUID) async {
        guard operationID == operation else { return }
        operationID = nil
        pendingPrimary = nil
        await primaryPreparer.close()
        await secondaryPreparer.close()
        state = .failedBeforeSession(classify(error))
    }

    /// operationが現行であることを検査します。
    /// - Parameter operation: callbackが捕捉したID。
    /// - Throws: 取消しまたはstaleなら`cancelled`。
    private func ensureCurrent(_ operation: UUID) throws {
        guard operationID == operation else { throw AcquisitionStartFailure.cancelled }
    }

    /// 新しいConnection Generationを発行します。
    /// - Returns: 単調増加するGeneration。
    private func nextGeneration() -> ConnectionGeneration {
        generationValue += 1
        return ConnectionGeneration(value: generationValue)
    }

    /// 任意Errorを安定失敗へ写像します。
    /// - Parameter error: 低水準Error。
    /// - Returns: 利用者表示可能な分類。
    private func classify(_ error: Error) -> AcquisitionStartFailure {
        error as? AcquisitionStartFailure ?? .preflightBlocked
    }
}
