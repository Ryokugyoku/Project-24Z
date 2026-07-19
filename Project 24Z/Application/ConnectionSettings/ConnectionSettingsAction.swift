/// 接続設定画面から通知できる型付き操作です。
nonisolated enum ConnectionSettingsAction: Equatable, Sendable {
    case load
    case beginDiscovery(role: CommunicationRole, transportKind: TransportEndpoint.Kind)
    case selectCandidate(ConnectionEndpointCandidate, role: CommunicationRole)
    case clearDefault(role: CommunicationRole)
    case cancelDiscovery
}
