/// Session作成前後を混同しないログ収集開始の安定失敗分類です。
nonisolated enum AcquisitionStartFailure: Error, Equatable, Sendable {
    case preflightBlocked
    case endpointNotFound
    case permissionDenied
    case transportUnavailable
    case adapterIdentityMismatch
    case adapterIdentityUnknown
    case adaptersNotDistinct
    case adapterUnsupported
    case allowlistUnavailable
    case rawCANReceiveOnlyUnverified
    case timedOut
    case cancelled
    case sessionCommitFailed
    case acquisitionFailedAfterCommit
}
