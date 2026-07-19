import Foundation

/// 一接続のread-only OBD識別とPID probeを終端したSnapshotです。
nonisolated struct OBDVehicleDiscoverySnapshot: Equatable, Sendable {
    /// 正規化前に一意性と形状を確認した17文字VINです。
    let vin: String

    /// VINを根拠付ける完全なAdapter応答です。
    let rawVINResponse: Data

    /// Adapterが確定した診断Protocolの非機密表示です。
    let diagnosticProtocol: String

    /// 固定allowlistのprobeで値取得まで成功したPIDだけです。
    let successfulPIDValues: [OBDLivePIDValue]

    /// Adapter identity照合結果です。
    let adapterIdentity: VerifiedAdapterIdentity

    /// 一接続一件を識別するprocess-local UUIDです。
    let connectionID: UUID
}
