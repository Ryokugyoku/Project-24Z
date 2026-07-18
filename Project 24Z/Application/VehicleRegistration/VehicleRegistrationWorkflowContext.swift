import Foundation

/// 登録transactionとSession bindingを接続するprocess内不変Contextです。
struct VehicleRegistrationWorkflowContext: Equatable, Sendable {
    /// 暗号・Digest準備済み登録要求です。
    let request: VehicleRegistrationRequest
    /// 接続Generationです。
    let connectionGeneration: ConnectionGeneration
    /// 最終識別attempt UUIDです。
    let scanAttemptID: UUID
    /// 現在Session UUIDです。
    let sessionID: UUID
    /// 未割当Sessionの期待Revisionです。
    let sessionRevision: Int
}
