import Foundation

/// 承認済みEndpointと固定allowlistを使い、車両busへ触れずAdapter identityだけを確認します。
nonisolated struct ELMAdapterIdentityProbe: AdapterIdentityProbing, Sendable {
    private let endpointLocator: any USBSerialEndpointLocating
    private let transport: any CommunicationTransport
    private let encoder: any ELMCommandEncoding

    /// Adapter単体識別Probeを構成します。
    /// - Parameters:
    ///   - endpointLocator: 承認済みDescriptorだけを返すEndpoint境界。
    ///   - transport: 115200/8N1で開くUSB serial transport。
    ///   - encoder: exact command bytesを固定するallowlist。
    init(
        endpointLocator: any USBSerialEndpointLocating,
        transport: any CommunicationTransport,
        encoder: any ELMCommandEncoding
    ) {
        self.endpointLocator = endpointLocator
        self.transport = transport
        self.encoder = encoder
    }

    /// 4つの承認済みHost-to-Adapter Requestを各一回実行し、必ずTransportを閉じます。
    /// - Returns: OBDLink EX r2.7.1／STN2232 v5.10.3と一致したidentity。
    /// - Throws: 候補数、応答、timeout、Transportのいずれかが不正な場合。
    func verifyApprovedAdapter() async throws -> VerifiedAdapterIdentity {
        let endpoints = try endpointLocator.locateApprovedEndpoints()
        guard endpoints.count == 1, let endpoint = endpoints.first else {
            throw CommunicationRuntimeError.transportUnavailable
        }

        let generation = ConnectionGeneration(value: 1)
        let channel = SerializedELMCommandChannel(transport: transport, encoder: encoder)
        do {
            try await transport.open(endpoint: endpoint, generation: generation) { event in
                Task {
                    switch event {
                    case .received(let bytes):
                        await channel.receive(bytes, generation: generation)
                    case .disconnected, .failed:
                        await channel.disconnect(generation: generation)
                    case .connected:
                        break
                    }
                }
            }

            let boundary = try await channel.execute(
                request: .adapterInputBoundaryClear,
                generation: generation,
                timeout: .seconds(2)
            )
            try requirePrompt(boundary)

            let reset = try await channel.execute(
                request: .adapterInitializationReset,
                generation: generation,
                timeout: .seconds(2)
            )
            try require(reset, contains: "ELM327 v1.4b")

            let hardware = try await channel.execute(
                request: .adapterHardwareIdentification,
                generation: generation,
                timeout: .seconds(2)
            )
            try require(hardware, contains: "OBDLink EX r2.7.1")

            let firmware = try await channel.execute(
                request: .adapterFirmwareIdentification,
                generation: generation,
                timeout: .seconds(2)
            )
            try require(firmware, contains: "STN2232 v5.10.3")

            await transport.close()
            return VerifiedAdapterIdentity(
                displayName: "OBDLink EX (EX101)",
                hardwareVersion: "OBDLink EX r2.7.1",
                firmwareVersion: "STN2232 v5.10.3"
            )
        } catch {
            await transport.close()
            throw error
        }
    }

    /// 進行中channelの完了を待たず、基底Transportを閉じます。
    func cancel() async {
        await transport.close()
    }

    /// Prompt終端以外を成功扱いしません。
    /// - Parameter envelope: 未加工応答を保持するEnvelope。
    /// - Throws: prompt終端でなければ`malformedResponse`。
    private func requirePrompt(_ envelope: ELMResponseEnvelope) throws {
        guard envelope.completion == .prompt, envelope.promptRange != nil else {
            throw CommunicationRuntimeError.malformedResponse
        }
    }

    /// Prompt終端と承認済みASCII断片の両方を要求します。
    /// - Parameters:
    ///   - envelope: 未加工応答を保持するEnvelope。
    ///   - expected: transcriptで確定した非機密identity文字列。
    /// - Throws: 応答が完全条件を満たさない場合は`adapterIdentityUnknown`。
    private func require(_ envelope: ELMResponseEnvelope, contains expected: String) throws {
        try requirePrompt(envelope)
        guard let text = String(data: envelope.rawBytes, encoding: .utf8),
              text.contains(expected) else {
            throw CommunicationRuntimeError.adapterIdentityUnknown
        }
    }
}
