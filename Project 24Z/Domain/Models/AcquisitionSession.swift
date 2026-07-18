import Foundation

/// 一回の明示的な取得と車両所属を表す永続Sessionです。
struct AcquisitionSession: Equatable, Sendable {
    /// 車両所属の確定状態です。
    enum VehicleBindingState: String, Sendable { case registeredConfirmed = "registered_confirmed"; case unassignedUnidentified = "unassigned_unidentified"; case unassignedConflict = "unassigned_conflict" }
    /// 取得処理の状態です。
    enum CaptureState: String, Sendable { case recording; case stopRequested = "stop_requested"; case endedCleanly = "ended_cleanly"; case recoveryRequired = "recovery_required" }
    /// 保存判断の状態です。
    enum DispositionState: String, Sendable { case pendingDecision = "pending_decision"; case saved; case discardPending = "discard_pending"; case discarded; case deletePending = "delete_pending"; case deleted }
    /// 保存内容の検証状態です。
    enum IntegrityState: String, Sendable { case unchecked; case verified; case attentionRequired = "attention_required"; case unavailable }
    /// 取得終端の安定理由です。
    enum EndReason: String, Sendable { case userStop = "user_stop"; case storageCritical = "storage_critical"; case applicationTermination = "application_termination"; case processTermination = "process_termination"; case deviceRestart = "device_restart"; case writePipelineFailure = "write_pipeline_failure"; case unknown }

    let sessionID: UUID
    let vehicleID: UUID?
    let vehicleBindingState: VehicleBindingState
    let captureState: CaptureState
    let dispositionState: DispositionState
    let integrityState: IntegrityState
    let endReason: EndReason?
    let startedAt: Date
    let endedAt: Date?
    let createdByDeviceID: UUID
    let revision: Int
    let updatedAt: Date
    let updatedByDeviceID: UUID
}
