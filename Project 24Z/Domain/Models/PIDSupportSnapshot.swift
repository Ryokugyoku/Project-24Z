import Foundation

/// VersionとGenerationを固定したECU別support探索の終端Snapshotです。
nonisolated struct PIDSupportSnapshot: Equatable, Sendable {
    /// Snapshot UUIDです。
    let snapshotID: UUID
    /// 接続Generationです。
    let connectionGeneration: ConnectionGeneration
    /// Catalog bundle Versionです。
    let catalogVersion: String
    /// support探索規則Versionです。
    let discoveryRuleVersion: String
    /// ECU別結果です。
    let observations: [PIDSupportObservation]
    /// 系列を完遂したかを示します。
    let isComplete: Bool
}
