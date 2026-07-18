#if os(macOS)
import Foundation

/// USB／Bluetoothの実Adapter証拠がないProduction経路を明示的に拒否します。
struct MacOSUnavailableTransport: CommunicationTransport, Sendable {
    /// 未検証経路をopenしません。
    /// - Parameters:
    ///   - endpoint: 拒否対象Endpoint。
    ///   - generation: 接続Generation。
    ///   - eventHandler: 呼び出さないcallback。
    /// - Throws: 常に`transportUnavailable`。
    func open(endpoint: TransportEndpoint, generation: ConnectionGeneration, eventHandler: @escaping @Sendable (TransportEvent) -> Void) async throws {
        throw CommunicationRuntimeError.transportUnavailable
    }

    /// 未検証経路へbytesを送りません。
    /// - Parameters:
    ///   - bytes: 送信しないbytes。
    ///   - generation: 接続Generation。
    /// - Throws: 常に`transportUnavailable`。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws { throw CommunicationRuntimeError.transportUnavailable }

    /// 確保済み資源がないため何もしません。
    func close() async {}
}
#endif
