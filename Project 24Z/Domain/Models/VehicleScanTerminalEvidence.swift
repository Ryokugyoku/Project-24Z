import Foundation

/// connection-level builderが一度だけ作る最終終端Evidenceです。
nonisolated struct VehicleScanTerminalEvidence: Equatable, Sendable {
    /// 業務Scan UUIDです。
    let scanID: UUID
    /// 一接続一件のOBD接続UUIDです。
    let obdConnectionID: UUID
    /// 接続Generationです。
    let connectionGeneration: ConnectionGeneration
    /// 最後に採用したattempt UUIDです。
    let finalAttemptID: UUID
    /// 全attempt UUIDです。中間業務Scanとは表現しません。
    let attemptIDs: [UUID]
    /// 最終Snapshotに含まれる候補です。
    let candidates: [VehicleIdentifierCandidate]
    /// 終端時刻です。
    let finishedAt: Date
    /// 完遂したかを示します。
    let isComplete: Bool
}
