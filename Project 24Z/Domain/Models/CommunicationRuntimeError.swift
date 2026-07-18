/// Runtime境界が画面とテストへ公開する安定失敗分類です。
nonisolated enum CommunicationRuntimeError: Error, Equatable, Sendable {
    case transportUnavailable
    case staleGeneration
    case commandTimedOut
    case commandCancelled
    case commandChannelBusy
    case commandNotAllowlisted
    case malformedResponse
    case rawReceiveSafetyUnverified
    case adapterAlreadyAssigned
    case adapterIdentityUnknown
    case roleChangeRequiresNewSession
    case vehicleReidentificationRequired
    case vehicleIdentityMismatch
    case storageUnavailable
}
