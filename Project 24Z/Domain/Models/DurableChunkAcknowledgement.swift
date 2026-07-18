import Foundation

/// file確定とGRDB目録commitの両方を満たした場合だけ返すACKです。
struct DurableChunkAcknowledgement: Equatable, Sendable {
    let chunkID: UUID
    let ciphertextDigest: Data
    let catalogDigest: Data
}
