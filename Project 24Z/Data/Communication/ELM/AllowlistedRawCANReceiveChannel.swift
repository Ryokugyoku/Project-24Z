import Foundation

/// 検証済み制御commandだけを使い、車両bus送信APIを持たないRaw受信channelです。
actor AllowlistedRawCANReceiveChannel: RawCANReceiveChannel {
    private let transport: any CommunicationTransport
    private let encoder: any ELMCommandEncoding
    private let generation: ConnectionGeneration
    private var events: [RawCANEvent] = []
    private var waiters: [CheckedContinuation<RawCANEvent?, Never>] = []
    private var listening = false

    /// Transport、allowlist、接続Generationを固定します。
    /// - Parameters:
    ///   - transport: Secondary専用Transport。
    ///   - encoder: Raw start／stopを含む検証済みallowlist。
    ///   - generation: Secondary接続Generation。
    init(transport: any CommunicationTransport, encoder: any ELMCommandEncoding, generation: ConnectionGeneration) {
        self.transport = transport
        self.encoder = encoder
        self.generation = generation
    }

    /// safety未確認ならbytes生成前にblockします。
    /// - Parameter configuration: monitor safety証拠。
    /// - Throws: safety未確認、allowlist拒否、Transport失敗。
    func startListening(configuration: RawCANListenConfiguration) async throws {
        guard configuration.safetyEvidence != .unknown else { throw CommunicationRuntimeError.rawReceiveSafetyUnverified }
        let bytes = try encoder.encode(.rawMonitorStart)
        try await transport.write(bytes, generation: generation)
        listening = true
    }

    /// FIFO順で次Eventを返します。
    /// - Returns: 受信Event。停止済みで残件がなければ`nil`。
    func nextEvent() async -> RawCANEvent? {
        if !events.isEmpty { return events.removeFirst() }
        if !listening { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }

    /// allowlist済み停止だけを試し、失敗時にresetへFallbackしません。
    func stopListening() async {
        if listening, let bytes = try? encoder.encode(.rawMonitorStop) {
            try? await transport.write(bytes, generation: generation)
        }
        listening = false
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume(returning: nil) }
    }

    /// Data parserが作ったRaw保持Eventを受信queueへ追加します。
    /// - Parameter event: Secondaryで受信したEvent。
    func ingest(_ event: RawCANEvent) {
        guard listening, event.generation == generation else { return }
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: event)
        } else {
            events.append(event)
        }
    }
}
