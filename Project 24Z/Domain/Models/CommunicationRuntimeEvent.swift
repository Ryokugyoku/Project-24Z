import Foundation

/// Runtimeが保存Application境界へ渡す受信事実です。Durable ACKではありません。
nonisolated enum CommunicationRuntimeEvent: Equatable, Sendable {
    case transportBytes(Data, generation: ConnectionGeneration)
    case elmResponse(ELMResponseEnvelope)
    case rawCAN(RawCANEvent)
    case disconnected(generation: ConnectionGeneration)
}
