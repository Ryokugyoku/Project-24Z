import Foundation

/// 圧縮・認証付き暗号化を上流で完了した不透明Chunk入力です。
struct PreparedAcquisitionChunk: Sendable {
    let reservation: AcquisitionChunkReservation
    let clockEpochID: UUID
    let firstMonotonicNanoseconds: Int64
    let lastMonotonicNanoseconds: Int64
    let plaintextSize: Int64
    let compressedSize: Int64
    let recordFormatVersion: Int
    let compressionFormatVersion: Int
    let encryptionFormatVersion: Int
    let keyVersion: Int
    let bytes: Data
}
