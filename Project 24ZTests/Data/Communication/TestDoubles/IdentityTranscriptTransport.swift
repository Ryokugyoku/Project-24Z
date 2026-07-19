import Foundation
@testable import Project_24Z

/// Adapter単体golden transcriptをwriteごとに返すbyte Transportです。
actor IdentityTranscriptTransport: CommunicationTransport {
    private var eventHandler: (@Sendable (TransportEvent) -> Void)?
    private let firmwareResponse: Data
    private(set) var writes: [Data] = []
    private(set) var closeCount = 0

    /// goldenまたはfault注入用firmware応答でFakeを構成します。
    /// - Parameter firmwareResponse: `STI` write時に返すRaw response。
    init(
        firmwareResponse: Data = Data("STI\rSTN2232 v5.10.3\r>".utf8)
    ) {
        self.firmwareResponse = firmwareResponse
    }

    /// Endpointを開きcallbackを保持します。
    /// - Parameters:
    ///   - endpoint: Fakeでは使用しないEndpoint。
    ///   - generation: Fakeでは使用しないGeneration。
    ///   - eventHandler: golden responseの通知先。
    func open(
        endpoint: TransportEndpoint,
        generation: ConnectionGeneration,
        eventHandler: @escaping @Sendable (TransportEvent) -> Void
    ) async throws {
        self.eventHandler = eventHandler
        eventHandler(.connected)
    }

    /// exact commandを記録し、対応するgolden responseを返します。
    /// - Parameters:
    ///   - bytes: allowlistが生成したcommand bytes。
    ///   - generation: Fakeでは使用しないGeneration。
    /// - Throws: 未知commandなら`commandNotAllowlisted`。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws {
        writes.append(bytes)
        let response: Data
        switch bytes {
        case Data("??\r".utf8):
            response = Data("?\r>".utf8)
        case Data("ATZ\r".utf8):
            response = Data("ATZ\rELM327 v1.4b\r>".utf8)
        case Data("STDI\r".utf8):
            response = Data("STDI\rOBDLink EX r2.7.1\r>".utf8)
        case Data("STI\r".utf8):
            response = firmwareResponse
        default:
            throw CommunicationRuntimeError.commandNotAllowlisted
        }
        eventHandler?(.received(response))
    }

    /// close回数を記録します。
    func close() async {
        closeCount += 1
        eventHandler = nil
    }

    /// 記録済みwrite配列を返します。
    /// - Returns: 実行順を保持したcommand bytes。
    func recordedWrites() -> [Data] {
        writes
    }

    /// 記録済みclose回数を返します。
    /// - Returns: close呼出回数。
    func recordedCloseCount() -> Int {
        closeCount
    }
}
