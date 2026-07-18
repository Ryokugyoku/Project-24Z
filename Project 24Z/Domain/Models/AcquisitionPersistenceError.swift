import Foundation

/// Acquisition保存が非破壊停止する安定エラー分類です。
enum AcquisitionPersistenceError: Error, Equatable, Sendable {
    case invalidRequest
    case conflict
    case storageCapacityCritical
    case partialWrite
    case verificationFailed
    case catalogCommitFailed
    case unavailable
}
