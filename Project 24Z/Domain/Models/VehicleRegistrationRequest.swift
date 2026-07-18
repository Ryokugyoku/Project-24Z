import Foundation

/// 暗号・Digest準備と読戻し検証を終えた不変の登録要求です。
nonisolated struct VehicleRegistrationRequest: Equatable, Sendable {
    /// 呼び出し側が新規登録時に使用する車両UUIDです。
    let proposedVehicleID: UUID
    /// 任意表示名の暗号文です。未指定時はnilです。
    let encryptedDisplayName: EncryptedVehicleValue?
    /// 有効性確認済みの登録根拠識別子です。
    let identifiers: [VehicleIdentifierEvidence]
    /// 一接続の最終Snapshotです。
    let scan: VehicleIdentificationScanSnapshot
    /// 変更主体の端末UUIDです。
    let deviceID: UUID
    /// DB記録日時です。
    let recordedAt: Date
    /// 既存候補確認時にtransaction内で再確認する車両UUIDです。
    let expectedCandidateVehicleID: UUID?
    /// 既存候補確認時にtransaction内で再確認するLifecycle Revisionです。
    let expectedCandidateLifecycleRevision: Int?

    /// 暗号準備済みの登録要求を生成します。
    /// - Parameters:
    ///   - proposedVehicleID: 新規時に使用する内部UUID。
    ///   - encryptedDisplayName: 任意表示名暗号文。
    ///   - identifiers: 有効性確認済みIdentifier群。
    ///   - scan: 一接続の最終Snapshot。
    ///   - deviceID: 記録端末UUID。
    ///   - recordedAt: 記録日時。
    ///   - expectedCandidateVehicleID: 既存候補UUID。
    ///   - expectedCandidateLifecycleRevision: 既存候補Lifecycle Revision。
    init(
        proposedVehicleID: UUID,
        encryptedDisplayName: EncryptedVehicleValue?,
        identifiers: [VehicleIdentifierEvidence],
        scan: VehicleIdentificationScanSnapshot,
        deviceID: UUID,
        recordedAt: Date,
        expectedCandidateVehicleID: UUID? = nil,
        expectedCandidateLifecycleRevision: Int? = nil
    ) {
        self.proposedVehicleID = proposedVehicleID
        self.encryptedDisplayName = encryptedDisplayName
        self.identifiers = identifiers
        self.scan = scan
        self.deviceID = deviceID
        self.recordedAt = recordedAt
        self.expectedCandidateVehicleID = expectedCandidateVehicleID
        self.expectedCandidateLifecycleRevision = expectedCandidateLifecycleRevision
    }
}
