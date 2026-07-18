/// Serialized ELM channelをPrimary読取専用APIへ狭めます。
actor AllowlistedOBDAcquisitionChannel: OBDAcquisitionChannel {
    private let channel: SerializedELMCommandChannel
    private let generation: ConnectionGeneration

    /// 接続Generationと直列channelを固定します。
    /// - Parameters:
    ///   - channel: Version付きallowlistを使用する直列ELM channel。
    ///   - generation: Primary接続Generation。
    init(channel: SerializedELMCommandChannel, generation: ConnectionGeneration) {
        self.channel = channel
        self.generation = generation
    }

    /// 読取用途だけを`.standardOBD`へ包んで実行します。
    /// - Parameters:
    ///   - request: DTC消去、write、ECU resetを持たないRequest。
    ///   - timeout: command deadline。
    /// - Returns: Raw応答Envelope。
    /// - Throws: allowlistまたは通信失敗。
    func request(_ request: OBDDiagnosticRequest, timeout: Duration) async throws -> ELMResponseEnvelope {
        try await channel.execute(request: .standardOBD(request), generation: generation, timeout: timeout)
    }
}
