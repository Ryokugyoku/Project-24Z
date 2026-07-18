import Foundation
@testable import Project_24Z

/// callback遅延、write失敗、接続失敗を注入できるTransport Fakeです。
actor FakeCommunicationTransport: CommunicationTransport {
    /// 注入可能な失敗位置です。
    enum Fault: Sendable { case none; case open; case write }

    private var handlers: [ConnectionGeneration: @Sendable (TransportEvent) -> Void] = [:]
    private(set) var writes: [(Data, ConnectionGeneration)] = []
    private(set) var closeCount = 0
    var fault: Fault = .none

    /// callbackをGeneration別に保持します。
    /// - Parameters:
    ///   - endpoint: Fakeでは記録しないEndpoint。
    ///   - generation: callbackの世代。
    ///   - eventHandler: 後から任意Eventを注入する通知先。
    /// - Throws: `fault == .open`なら利用不能。
    func open(endpoint: TransportEndpoint, generation: ConnectionGeneration, eventHandler: @escaping @Sendable (TransportEvent) -> Void) async throws {
        if fault == .open { throw CommunicationRuntimeError.transportUnavailable }
        handlers[generation] = eventHandler
    }

    /// 書込順とGenerationを記録します。
    /// - Parameters:
    ///   - bytes: 生成済みcommand bytes。
    ///   - generation: 書込世代。
    /// - Throws: `fault == .write`なら利用不能。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws {
        if fault == .write { throw CommunicationRuntimeError.transportUnavailable }
        writes.append((bytes, generation))
    }

    /// close回数を記録します。遅延callback試験のためhandlerは保持します。
    func close() async { closeCount += 1 }

    /// 指定Generationへcallbackを発火します。
    /// - Parameters:
    ///   - event: 注入するEvent。
    ///   - generation: 新旧を明示する世代。
    func emit(_ event: TransportEvent, generation: ConnectionGeneration) {
        handlers[generation]?(event)
    }

    /// 記録済みwrite件数を返します。
    /// - Returns: write呼出回数。
    func writeCount() -> Int { writes.count }

    /// 指定位置のwrite bytesを返します。
    /// - Parameter index: 0始まりの位置。
    /// - Returns: 記録済みbytes。
    func writtenBytes(at index: Int) -> Data { writes[index].0 }
}
