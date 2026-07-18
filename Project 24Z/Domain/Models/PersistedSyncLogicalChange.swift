import Foundation

/// DBで0始まりSequenceとChainへ確定したLogical Changeです。
struct PersistedSyncLogicalChange: Equatable, Sendable {
    let logicalChangeID: UUID
    let sequence: Int64
    let previousChangeID: UUID?
    let previousChainDigest: Data?
    let chainDigest: Data
}
