/// 接続設定の保存・探索境界が返す安定エラーです。
nonisolated enum ConnectionSettingsError: Error, Equatable, Sendable {
    case unavailable
    case invalidCandidate
    case duplicateRoleCandidate
    case scopeMismatch
    case staleRevision
    case permissionDenied
    case permissionRestricted
    case transportUnsupported
    case noCandidates
}
