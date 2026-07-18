import Foundation

/// immutable Chunk fileを参照するGRDB目録値です。
struct AcquisitionChunkCatalogEntry: Equatable, Sendable {
    let reservation: AcquisitionChunkReservation
    let clockEpochID: UUID
    let firstMonotonicNanoseconds: Int64
    let lastMonotonicNanoseconds: Int64
    let plaintextSize: Int64
    let compressedSize: Int64
    let ciphertextSize: Int64
    let recordFormatVersion: Int
    let compressionFormatVersion: Int
    let encryptionFormatVersion: Int
    let keyVersion: Int
    let ciphertextDigest: Data
    let catalogDigest: Data
    let relativePath: String
    let createdAt: Date
}
