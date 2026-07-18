/// 再接続候補が既存Adapterと同一かを推測せず表す判定です。
nonisolated enum AdapterIdentityEvidence: Equatable, Sendable {
    case sameAdapterConfirmed(AdapterReference)
    case differentAdapterConfirmed(AdapterReference)
    case unknown
}
