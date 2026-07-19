#if os(macOS)
import Foundation
@testable import Project_24Z

/// read-only車両Discoveryの固定応答をwriteごとに返すTransportです。
actor VehicleTranscriptTransport: CommunicationTransport {
    private var eventHandler: (@Sendable (TransportEvent) -> Void)?
    private let vinResponse: Data
    private(set) var writes: [Data] = []
    private(set) var closeCount = 0

    /// VIN応答を差し替え可能なgolden Transportを作ります。
    /// - Parameter vinResponse: `0902`に返す完全応答。
    init(vinResponse: Data = Data("014\r0: 49 02 01 31 48 47 43 4D\r1: 38 32 36 33 33 41 30\r2: 30 34 33 35 32\r>".utf8)) {
        self.vinResponse = vinResponse
    }

    /// callbackを保持して接続完了を通知します。
    /// - Parameters:
    ///   - endpoint: Fakeでは使用しないEndpoint。
    ///   - generation: Fakeでは使用しないGeneration。
    ///   - eventHandler: 応答通知先。
    func open(
        endpoint: TransportEndpoint,
        generation: ConnectionGeneration,
        eventHandler: @escaping @Sendable (TransportEvent) -> Void
    ) async throws {
        self.eventHandler = eventHandler
        eventHandler(.connected)
    }

    /// 固定allowlist commandだけを受理してgolden応答を返します。
    /// - Parameters:
    ///   - bytes: exact command bytes。
    ///   - generation: Fakeでは使用しないGeneration。
    /// - Throws: 未知commandの場合。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws {
        writes.append(bytes)
        let response: Data
        switch String(decoding: bytes, as: UTF8.self) {
        case "??\r": response = Data("?\r>".utf8)
        case "ATZ\r": response = Data("ELM327 v1.4b\r>".utf8)
        case "STDI\r": response = Data("OBDLink EX r2.7.1\r>".utf8)
        case "STI\r": response = Data("STN2232 v5.10.3\r>".utf8)
        case "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r": response = Data("OK\r>".utf8)
        case "0902\r": response = vinResponse
        case "ATDP\r": response = Data("ISO 15765-4 (CAN 11/500)\r>".utf8)
        case "0104\r": response = Data("41 04 7F\r>".utf8)
        case "0105\r": response = Data("41 05 64\r>".utf8)
        case "010C\r": response = Data("41 0C 0F A0\r>".utf8)
        case "010D\r": response = Data("41 0D 32\r>".utf8)
        default: throw CommunicationRuntimeError.commandNotAllowlisted
        }
        eventHandler?(.received(response))
    }

    /// closeを記録してcallbackを解放します。
    func close() async {
        closeCount += 1
        eventHandler = nil
    }

    /// exact write順を返します。
    /// - Returns: 全write bytes。
    func recordedWrites() -> [Data] { writes }

    /// close回数を返します。
    /// - Returns: close呼出回数。
    func recordedCloseCount() -> Int { closeCount }
}
#endif
