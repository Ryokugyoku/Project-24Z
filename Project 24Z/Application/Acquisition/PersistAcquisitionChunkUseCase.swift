import Foundation

/// immutable file確定後に目録をcommitし、Durable ACKを調停します。
struct PersistAcquisitionChunkUseCase {
    private let fileStore: any ImmutableChunkFileStore
    private let repository: any AcquisitionRepository
    private let catalogDigester: any AcquisitionChunkCatalogDigesting

    /// 三つの保存境界を注入します。
    /// - Parameters:
    ///   - fileStore: fileを先に確定するAdapter。
    ///   - repository: GRDB目録Adapter。
    ///   - catalogDigester: canonical目録Digest Adapter。
    init(
        fileStore: any ImmutableChunkFileStore,
        repository: any AcquisitionRepository,
        catalogDigester: any AcquisitionChunkCatalogDigesting
    ) {
        self.fileStore = fileStore
        self.repository = repository
        self.catalogDigester = catalogDigester
    }

    /// file内容と親directoryが永続化され、最終読戻しとDB commitが成功した場合だけACKします。
    /// - Parameters:
    ///   - chunk: 圧縮・暗号化準備済みの不透明Chunk。
    ///   - createdAt: 目録記録日時。
    /// - Returns: file digestと別のcatalog digestを含むDurable ACK。
    /// - Throws: 途中失敗時はACKせず、孤立fileまたはstagingを復旧可能なまま残します。
    func execute(chunk: PreparedAcquisitionChunk, createdAt: Date) throws -> DurableChunkAcknowledgement {
        let file = try fileStore.finalize(chunk)
        var entry = AcquisitionChunkCatalogEntry(
            reservation: chunk.reservation,
            clockEpochID: chunk.clockEpochID,
            firstMonotonicNanoseconds: chunk.firstMonotonicNanoseconds,
            lastMonotonicNanoseconds: chunk.lastMonotonicNanoseconds,
            plaintextSize: chunk.plaintextSize,
            compressedSize: chunk.compressedSize,
            ciphertextSize: file.byteCount,
            recordFormatVersion: chunk.recordFormatVersion,
            compressionFormatVersion: chunk.compressionFormatVersion,
            encryptionFormatVersion: chunk.encryptionFormatVersion,
            keyVersion: chunk.keyVersion,
            ciphertextDigest: file.ciphertextDigest,
            catalogDigest: Data(repeating: 0, count: 32),
            relativePath: file.relativePath,
            createdAt: createdAt
        )
        entry = AcquisitionChunkCatalogEntry(
            reservation: entry.reservation,
            clockEpochID: entry.clockEpochID,
            firstMonotonicNanoseconds: entry.firstMonotonicNanoseconds,
            lastMonotonicNanoseconds: entry.lastMonotonicNanoseconds,
            plaintextSize: entry.plaintextSize,
            compressedSize: entry.compressedSize,
            ciphertextSize: entry.ciphertextSize,
            recordFormatVersion: entry.recordFormatVersion,
            compressionFormatVersion: entry.compressionFormatVersion,
            encryptionFormatVersion: entry.encryptionFormatVersion,
            keyVersion: entry.keyVersion,
            ciphertextDigest: entry.ciphertextDigest,
            catalogDigest: try catalogDigester.digest(for: entry),
            relativePath: entry.relativePath,
            createdAt: entry.createdAt
        )
        let reread = try repository.commitChunk(entry)
        guard reread == entry else { throw AcquisitionPersistenceError.catalogCommitFailed }
        return DurableChunkAcknowledgement(
            chunkID: entry.reservation.chunkID,
            ciphertextDigest: entry.ciphertextDigest,
            catalogDigest: entry.catalogDigest
        )
    }
}
