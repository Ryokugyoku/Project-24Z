import Foundation

/// fsync、rename、最終読戻しまで完了したChunk file情報です。
struct FinalizedChunkFile: Equatable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let ciphertextDigest: Data
}
