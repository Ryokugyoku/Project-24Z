/// 一接続Runtimeの外部可視状態です。
nonisolated enum ConnectionRuntimeState: Equatable, Sendable {
    case idle
    case connecting(ConnectionGeneration)
    case ready(ConnectionGeneration)
    case acquiring(ConnectionGeneration)
    case reconnectWait(ConnectionGeneration)
    case blocked(CommunicationRuntimeError)
    case failed(CommunicationRuntimeError)
}
