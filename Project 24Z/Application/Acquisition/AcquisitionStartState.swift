import Foundation

/// ダッシュボードが表示するログ収集開始・取得状態です。
nonisolated enum AcquisitionStartState: Equatable, Sendable {
    case idle
    case preflight
    case preparingPrimary
    case preparingSecondary
    case awaitingPIDOnlyConfirmation(failure: AcquisitionStartFailure)
    case committingSession
    case acquiringPID(sessionID: UUID)
    case acquiringPIDAndRawCAN(sessionID: UUID)
    case stopping(sessionID: UUID)
    case stopped(sessionID: UUID)
    case stopRecoveryRequired(sessionID: UUID, failure: AcquisitionStopFailure)
    case stopStateUnknown(sessionID: UUID, failure: AcquisitionStopFailure)
    case failedBeforeSession(AcquisitionStartFailure)
    case failedAfterSession(sessionID: UUID, failure: AcquisitionStartFailure)
    case cancelled
}
