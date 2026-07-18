import Foundation

/// 一つのprocess内単調時計名前空間を表します。
struct AcquisitionClockEpoch: Equatable, Sendable {
    let clockEpochID: UUID
    let sessionID: UUID
    let processInstanceID: UUID
    let deviceID: UUID
    let wallClockAnchor: Date
    let anchorUncertaintyNanoseconds: Int64
    let startedAt: Date
}
