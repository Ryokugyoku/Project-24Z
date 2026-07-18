import Foundation

/// 暗号・Digest準備と読戻し検証を終えた不変の登録要求です。
struct VehicleRegistrationRequest: Equatable, Sendable {
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
}
