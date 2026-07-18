import Foundation

/// Stream内で取得または永続化保証を失った区間です。
struct AcquisitionGap: Equatable, Sendable {
    /// 欠損の安定原因です。
    enum Reason: String, Sendable { case adapterDisconnected = "adapter_disconnected"; case transportInterrupted = "transport_interrupted"; case iOSApplicationTermination = "ios_background_or_application_termination"; case macOSProcessTermination = "macos_sleep_or_process_termination"; case reconnectionInProgress = "reconnection_in_progress"; case bufferDrop = "buffer_overflow_or_processing_drop"; case storageCapacityCritical = "storage_capacity_critical"; case writeFailure = "write_encryption_or_integrity_failure"; case userPaused = "user_paused"; case unknown }
    /// 欠損を観測した方法です。
    enum DetectionMethod: String, Sendable { case transportEvent = "transport_event"; case lifecycleEvent = "lifecycle_event"; case sequenceAudit = "sequence_audit"; case bufferAccounting = "buffer_accounting"; case storageMonitor = "storage_monitor"; case writeVerification = "write_verification"; case startupRecovery = "startup_recovery"; case userAction = "user_action"; case unknown }
    /// 境界時刻の確度です。
    enum Certainty: String, Sendable { case confirmed; case estimated }

    let gapID: UUID
    let sessionID: UUID
    let streamID: UUID
    let reason: Reason
    let detectionMethod: DetectionMethod
    let startCertainty: Certainty
    let startClockEpochID: UUID
    let startMonotonicNanoseconds: Int64?
    let startAt: Date
    let firstMissingSequence: Int64?
    let missingRecordCount: Int64?
    let createdAt: Date
}
