import Foundation

/// Platform Transportから接続ownerへ渡す低水準Eventです。
nonisolated enum TransportEvent: Equatable, Sendable {
    case connected
    case received(Data)
    case disconnected
    case failed
}
