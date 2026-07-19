#if os(macOS)
import Foundation

/// OBDLink EXで承認済みread-only要求をFIFO実行するmacOS車両Discoveryです。
actor OBDLinkEXVehicleDiscovery: OBDVehicleDiscovering {
    private let endpointLocator: any USBSerialEndpointLocating
    private let transport: any CommunicationTransport
    private let encoder: any ELMCommandEncoding

    /// USB endpoint、serial Transport、固定allowlistを構成します。
    /// - Parameters:
    ///   - endpointLocator: Descriptor完全一致のEndpoint列挙境界。
    ///   - transport: 115200/8N1 Transport。
    ///   - encoder: 任意commandを拒否する固定allowlist。
    init(
        endpointLocator: any USBSerialEndpointLocating,
        transport: any CommunicationTransport,
        encoder: any ELMCommandEncoding = OBDLinkEXVehicleCommandAllowlist.version1
    ) {
        self.endpointLocator = endpointLocator
        self.transport = transport
        self.encoder = encoder
    }

    /// Adapter identity、VIN、最小PID値を一接続で取得し、成否にかかわらずcloseします。
    /// - Returns: 一意なVINと値取得成功PIDだけを持つSnapshot。
    /// - Throws: Descriptor、identity、prompt、VIN一意性、Transport失敗。
    func discoverVehicle() async throws -> OBDVehicleDiscoverySnapshot {
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

            _ = try await requirePrompt(channel, .adapterInputBoundaryClear, generation: generation, timeout: .seconds(2))
            let reset = try await requirePrompt(channel, .adapterInitializationReset, generation: generation, timeout: .seconds(3))
            try requireText(reset, contains: "ELM327 v1.4b")
            let hardware = try await requirePrompt(channel, .adapterHardwareIdentification, generation: generation, timeout: .seconds(2))
            try requireText(hardware, contains: "OBDLink EX r2.7.1")
            let firmware = try await requirePrompt(channel, .adapterFirmwareIdentification, generation: generation, timeout: .seconds(2))
            try requireText(firmware, contains: "STN2232 v5.10.3")

            for command in [ELMCommandRequest.adapterEchoOff, .adapterLinefeedsOff, .adapterSpacesOn, .adapterHeadersOff, .adapterProtocolAutomatic] {
                let response = try await requirePrompt(channel, command, generation: generation, timeout: .seconds(2))
                try requireText(response, contains: "OK")
            }

            let vinResponse = try await requirePrompt(
                channel,
                .standardOBD(.init(purpose: .vehicleIdentification(parameter: 0x02))),
                generation: generation,
                timeout: .seconds(20)
            )
            let vin = try Self.decodeUniqueVIN(from: vinResponse.rawBytes)
            let protocolResponse = try await requirePrompt(channel, .adapterProtocolDescription, generation: generation, timeout: .seconds(2))
            let diagnosticProtocol = Self.protocolDescription(from: protocolResponse.rawBytes)

            var readings: [OBDLivePIDValue] = []
            for parameter in [UInt8(0x04), 0x05, 0x0C, 0x0D] {
                let response = try await requirePrompt(
                    channel,
                    .standardOBD(.init(purpose: .currentData(parameter: parameter))),
                    generation: generation,
                    timeout: .seconds(5)
                )
                if let value = Self.decodePID(parameter, from: response.rawBytes, observedAt: Date()) {
                    readings.append(value)
                }
            }

            await transport.close()
            return OBDVehicleDiscoverySnapshot(
                vin: vin,
                rawVINResponse: vinResponse.rawBytes,
                diagnosticProtocol: diagnosticProtocol,
                successfulPIDValues: readings,
                adapterIdentity: .init(
                    displayName: "OBDLink EX (EX101)",
                    hardwareVersion: "OBDLink EX r2.7.1",
                    firmwareVersion: "STN2232 v5.10.3"
                ),
                connectionID: UUID()
            )
        } catch {
            await transport.close()
            throw error
        }
    }

    /// 進行中Transportを閉じます。
    func cancel() async {
        await transport.close()
    }

    /// 一Requestを実行しprompt終端を必須にします。
    /// - Parameters:
    ///   - channel: FIFO command channel。
    ///   - request: 固定allowlist内のRequest。
    ///   - generation: 現接続世代。
    ///   - timeout: command deadline。
    /// - Returns: Raw応答Envelope。
    /// - Throws: timeout、切断、prompt欠落。
    private func requirePrompt(
        _ channel: SerializedELMCommandChannel,
        _ request: ELMCommandRequest,
        generation: ConnectionGeneration,
        timeout: Duration
    ) async throws -> ELMResponseEnvelope {
        let response = try await channel.execute(request: request, generation: generation, timeout: timeout)
        guard response.completion == .prompt, response.promptRange != nil else {
            throw CommunicationRuntimeError.malformedResponse
        }
        return response
    }

    /// Identityまたは初期化応答に期待文字列があることを確認します。
    /// - Parameters:
    ///   - response: 完全Raw応答。
    ///   - expected: 非機密な固定応答断片。
    /// - Throws: UTF-8でない、または不一致の場合。
    private func requireText(_ response: ELMResponseEnvelope, contains expected: String) throws {
        guard let text = String(data: response.rawBytes, encoding: .utf8), text.contains(expected) else {
            throw CommunicationRuntimeError.malformedResponse
        }
    }

    /// Service 09 PID 02応答から一意な17文字VINだけを返します。
    /// - Parameter raw: Adapterの完全Raw応答。
    /// - Returns: 大文字化したVIN。
    /// - Throws: VINなし、不正文字、複数候補の場合。
    private static func decodeUniqueVIN(from raw: Data) throws -> String {
        let bytes = hexBytes(in: raw)
        var candidates = Set<String>()
        var index = 0
        while index + 2 < bytes.count {
            guard bytes[index] == 0x49, bytes[index + 1] == 0x02, bytes[index + 2] == 0x01 else {
                index += 1
                continue
            }
            var characters: [UInt8] = []
            var cursor = index + 3
            while cursor < bytes.count, characters.count < 17 {
                let byte = bytes[cursor]
                if (48...57).contains(byte) || (65...90).contains(byte) {
                    characters.append(byte)
                }
                cursor += 1
            }
            if characters.count == 17,
               let value = String(bytes: characters, encoding: .ascii),
               !value.contains(where: { "IOQ".contains($0) }) {
                candidates.insert(value)
            }
            index = cursor
        }
        guard candidates.count == 1, let vin = candidates.first else {
            throw CommunicationRuntimeError.malformedResponse
        }
        return vin
    }

    /// 4つの承認済みService 01応答だけを標準式でDecodeします。
    /// - Parameters:
    ///   - parameter: 固定PID code。
    ///   - raw: 完全Raw応答。
    ///   - observedAt: 応答受理時刻。
    /// - Returns: 値取得成功時の表示可能値。NO DATAや形状不一致はnil。
    private static func decodePID(_ parameter: UInt8, from raw: Data, observedAt: Date) -> OBDLivePIDValue? {
        let bytes = hexBytes(in: raw)
        guard let marker = bytes.indices.first(where: {
            $0 + 1 < bytes.count && bytes[$0] == 0x41 && bytes[$0 + 1] == parameter
        }) else { return nil }
        let payload = Array(bytes.dropFirst(marker + 2))
        let decoded: (String, Double, String)?
        switch parameter {
        case 0x04 where payload.count >= 1:
            decoded = ("エンジン負荷", Double(payload[0]) * 100.0 / 255.0, "%")
        case 0x05 where payload.count >= 1:
            decoded = ("冷却水温", Double(payload[0]) - 40.0, "°C")
        case 0x0C where payload.count >= 2:
            decoded = ("エンジン回転数", Double(Int(payload[0]) * 256 + Int(payload[1])) / 4.0, "rpm")
        case 0x0D where payload.count >= 1:
            decoded = ("車速", Double(payload[0]), "km/h")
        default:
            decoded = nil
        }
        guard let decoded else { return nil }
        return .init(
            parameter: parameter,
            displayName: decoded.0,
            value: decoded.1,
            unit: decoded.2,
            rawResponse: raw,
            observedAt: observedAt
        )
    }

    /// ASCII応答から2桁hex tokenだけを抽出します。
    /// - Parameter raw: promptを含む完全応答。
    /// - Returns: sequence prefixや長さ行を除外したbyte列。
    private static func hexBytes(in raw: Data) -> [UInt8] {
        guard let text = String(data: raw, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: { !$0.isHexDigit })
            .compactMap { token in
                guard token.count == 2 else { return nil }
                return UInt8(token, radix: 16)
            }
    }

    /// ATDP応答からecho、prompt、空行を除いたProtocol表示を返します。
    /// - Parameter raw: ATDP完全応答。
    /// - Returns: 非機密なProtocol文字列。
    private static func protocolDescription(from raw: Data) -> String {
        guard let text = String(data: raw, encoding: .utf8) else { return "unknown" }
        return text
            .replacingOccurrences(of: ">", with: "")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map(String.init)
            .first(where: { !$0.isEmpty && !$0.uppercased().hasPrefix("ATDP") })
            ?? "unknown"
    }
}
#endif
