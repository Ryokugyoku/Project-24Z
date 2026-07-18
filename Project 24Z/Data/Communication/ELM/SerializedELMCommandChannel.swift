import Foundation

/// 一Transport上のELM commandをFIFOで一件ずつ実行するactorです。
actor SerializedELMCommandChannel {
    /// FIFOで待機中の一commandと完了継続を保持します。
    private struct Pending {
        let request: ELMCommandRequest
        let correlationID: UUID
        let generation: ConnectionGeneration
        let timeout: Duration
        let continuation: CheckedContinuation<ELMResponseEnvelope, Error>
    }

    /// 現在送信済みのcommand、応答framer、timeout監視を保持します。
    private struct Inflight {
        let pending: Pending
        let sequence: UInt64
        var framer: ELMResponseFramer
        var timeoutTask: Task<Void, Never>?
    }

    private let transport: any CommunicationTransport
    private let encoder: any ELMCommandEncoding
    private let classifier = ELMResponseClassifier()
    private var pending: [Pending] = []
    private var inflight: Inflight?
    private var nextSequence: UInt64 = 1
    private var boundaryEstablished = true

    /// Transportとallowlist encoderを注入します。
    /// - Parameters:
    ///   - transport: 現在接続を所有するbyte Transport。
    ///   - encoder: 検証済み用途だけをbytesへ変換するencoder。
    init(transport: any CommunicationTransport, encoder: any ELMCommandEncoding) {
        self.transport = transport
        self.encoder = encoder
    }

    /// RequestをFIFOへ追加し、prompt、timeout、取消しのいずれかまで待ちます。
    /// - Parameters:
    ///   - request: 任意文字列を含まない用途別Request。
    ///   - generation: 現在接続Generation。
    ///   - timeout: 呼出側Policyが決めたcommand deadline。
    /// - Returns: Rawを保持した応答Envelope。
    /// - Throws: allowlist拒否、Transport失敗、またはtask取消し。
    func execute(request: ELMCommandRequest, generation: ConnectionGeneration, timeout: Duration) async throws -> ELMResponseEnvelope {
        guard boundaryEstablished else { throw CommunicationRuntimeError.malformedResponse }
        let correlationID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(request: request, correlationID: correlationID, generation: generation, timeout: timeout, continuation: continuation))
                startNextIfNeeded()
            }
        } onCancel: {
            Task { await self.cancel(correlationID: correlationID) }
        }
    }

    /// Transport callbackから現在commandへbytesを追加します。
    /// - Parameters:
    ///   - bytes: 未加工受信bytes。
    ///   - generation: callbackが捕捉したGeneration。
    func receive(_ bytes: Data, generation: ConnectionGeneration) {
        guard var current = inflight, current.pending.generation == generation else { return }
        guard let framed = current.framer.append(bytes) else {
            inflight = current
            return
        }
        inflight = current
        finish(raw: framed.raw, promptRange: framed.promptRange, completion: .prompt)
    }

    /// Transport切断時に現在commandをpartial Raw付きで終端します。
    /// - Parameter generation: 切断callbackのGeneration。
    func disconnect(generation: ConnectionGeneration) {
        guard var current = inflight, current.pending.generation == generation else { return }
        let raw = current.framer.drainPartial()
        inflight = current
        finish(raw: raw, promptRange: nil, completion: .disconnected)
    }

    /// 外部のdrain／再初期化が完了した後だけcommand境界を再び有効化します。
    func reestablishBoundary() {
        guard inflight == nil else { return }
        boundaryEstablished = true
        startNextIfNeeded()
    }

    /// queue先頭をinflightへ進め、書込とtimeout監視を開始します。
    private func startNextIfNeeded() {
        guard inflight == nil, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        let sequence = nextSequence
        nextSequence += 1
        do {
            let bytes = try encoder.encode(item.request)
            let timeoutTask = Task { [timeout = item.timeout, correlationID = item.correlationID] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.timeout(correlationID: correlationID)
            }
            inflight = Inflight(pending: item, sequence: sequence, framer: ELMResponseFramer(), timeoutTask: timeoutTask)
            Task {
                do { try await transport.write(bytes, generation: item.generation) }
                catch { self.failWrite(correlationID: item.correlationID, error: error) }
            }
        } catch {
            item.continuation.resume(throwing: error)
            startNextIfNeeded()
        }
    }

    /// timeoutしたinflightをpartial Raw付きで完了します。
    /// - Parameter correlationID: 対象command相関ID。
    private func timeout(correlationID: UUID) {
        guard var current = inflight, current.pending.correlationID == correlationID else { return }
        let raw = current.framer.drainPartial()
        inflight = current
        finish(raw: raw, promptRange: nil, completion: .timedOut)
    }

    /// 取消されたqueue項目またはinflightを完了します。
    /// - Parameter correlationID: 取消対象の相関ID。
    private func cancel(correlationID: UUID) {
        if let index = pending.firstIndex(where: { $0.correlationID == correlationID }) {
            let item = pending.remove(at: index)
            item.continuation.resume(throwing: CancellationError())
            return
        }
        guard var current = inflight, current.pending.correlationID == correlationID else { return }
        let raw = current.framer.drainPartial()
        inflight = current
        finish(raw: raw, promptRange: nil, completion: .cancelled)
    }

    /// Transport write失敗を呼出元へ返します。
    /// - Parameters:
    ///   - correlationID: 対象command相関ID。
    ///   - error: Transportが返した失敗。
    private func failWrite(correlationID: UUID, error: Error) {
        guard let current = inflight, current.pending.correlationID == correlationID else { return }
        current.timeoutTask?.cancel()
        inflight = nil
        boundaryEstablished = false
        current.pending.continuation.resume(throwing: error)
        failPendingAfterBoundaryLoss()
    }

    /// 現在commandのEnvelopeを作成して次queueへ進みます。
    /// - Parameters:
    ///   - raw: 応答の全Raw bytes。
    ///   - promptRange: promptが存在する範囲。
    ///   - completion: 終端理由。
    private func finish(raw: Data, promptRange: Range<Int>?, completion: ELMResponseEnvelope.Completion) {
        guard let current = inflight else { return }
        current.timeoutTask?.cancel()
        inflight = nil
        let envelope = ELMResponseEnvelope(commandSequence: current.sequence, correlationID: current.pending.correlationID, generation: current.pending.generation, rawBytes: raw, promptRange: promptRange, classification: classifier.classify(raw), completion: completion)
        current.pending.continuation.resume(returning: envelope)
        if completion == .prompt {
            startNextIfNeeded()
        } else {
            boundaryEstablished = false
            failPendingAfterBoundaryLoss()
        }
    }

    /// timeout等で相関境界を失った後続commandをwriteせず失敗させます。
    private func failPendingAfterBoundaryLoss() {
        let abandoned = pending
        pending.removeAll()
        abandoned.forEach { $0.continuation.resume(throwing: CommunicationRuntimeError.malformedResponse) }
    }
}
