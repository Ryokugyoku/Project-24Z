import CryptoKit
import Foundation

/// 長さ付きcanonical binary encodingでChunk目録Digestを計算します。
struct SHA256AcquisitionChunkCatalogDigester: AcquisitionChunkCatalogDigesting {
    /// canonical SHA-256実装を構成します。
    init() {}

    /// file bytesそのものではなく全目録値を順序固定でDigest化します。
    /// - Parameter entry: Digest欄だけを除いて符号化する目録値。
    /// - Returns: 32 byte SHA-256。
    /// - Throws: 数値や相対パスが契約外の場合`invalidRequest`。
    func digest(for entry: AcquisitionChunkCatalogEntry) throws -> Data {
        guard entry.ciphertextDigest.count == 32,
              entry.catalogDigest.count == 32,
              !entry.relativePath.isEmpty,
              !entry.relativePath.hasPrefix("/"),
              !entry.relativePath.split(separator: "/").contains("..") else {
            throw AcquisitionPersistenceError.invalidRequest
        }
        var bytes = Data("P24Z-CATALOG-V1".utf8)
        append(entry.reservation.sessionID.uuidString.lowercased(), to: &bytes)
        append(entry.reservation.streamID.uuidString.lowercased(), to: &bytes)
        append(entry.reservation.chunkID.uuidString.lowercased(), to: &bytes)
        append(entry.reservation.chunkSequence, to: &bytes)
        append(entry.reservation.firstRecordSequence, to: &bytes)
        append(entry.reservation.lastRecordSequence, to: &bytes)
        append(entry.clockEpochID.uuidString.lowercased(), to: &bytes)
        append(entry.firstMonotonicNanoseconds, to: &bytes)
        append(entry.lastMonotonicNanoseconds, to: &bytes)
        append(entry.plaintextSize, to: &bytes)
        append(entry.compressedSize, to: &bytes)
        append(entry.ciphertextSize, to: &bytes)
        append(Int64(entry.recordFormatVersion), to: &bytes)
        append(Int64(entry.compressionFormatVersion), to: &bytes)
        append(Int64(entry.encryptionFormatVersion), to: &bytes)
        append(Int64(entry.keyVersion), to: &bytes)
        append(entry.ciphertextDigest, to: &bytes)
        append(entry.relativePath, to: &bytes)
        append(Int64((entry.createdAt.timeIntervalSince1970 * 1_000_000).rounded()), to: &bytes)
        append("available", to: &bytes)
        append(1, to: &bytes)
        return Data(SHA256.hash(data: bytes))
    }

    /// UTF-8文字列を長さ付きで追記します。
    /// - Parameters:
    ///   - value: 追記する文字列。
    ///   - data: 出力先。
    private func append(_ value: String, to data: inout Data) {
        append(Data(value.utf8), to: &data)
    }

    /// bytesを長さ付きで追記します。
    /// - Parameters:
    ///   - value: 追記するbytes。
    ///   - data: 出力先。
    private func append(_ value: Data, to data: inout Data) {
        append(Int64(value.count), to: &data)
        data.append(value)
    }

    /// signed 64-bit値をbig endianで追記します。
    /// - Parameters:
    ///   - value: 追記する値。
    ///   - data: 出力先。
    private func append(_ value: Int64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
