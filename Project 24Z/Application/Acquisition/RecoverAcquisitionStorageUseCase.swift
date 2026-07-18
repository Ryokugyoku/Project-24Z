import Foundation

/// 起動時にSession状態、staging、孤立file、欠落目録を非破壊で照合します。
struct RecoverAcquisitionStorageUseCase {
    private let fileStore: any ImmutableChunkFileStore
    private let repository: any AcquisitionRepository

    /// fileとGRDBの独立Adapterを注入します。
    init(fileStore: any ImmutableChunkFileStore, repository: any AcquisitionRepository) {
        self.fileStore = fileStore
        self.repository = repository
    }

    /// 未終端Sessionを終了し、曖昧fileを隔離、欠落目録をmissingへ進めます。
    /// - Parameters:
    ///   - recoveredAt: 復旧観測日時。
    ///   - deviceID: 復旧端末UUID。
    /// - Throws: 一段階でも保全記録できない場合に明示停止します。
    func execute(recoveredAt: Date, deviceID: UUID) throws {
        _ = try repository.recoverInterruptedSessions(at: recoveredAt, deviceID: deviceID)
        for quarantinePath in try fileStore.quarantineStagingFiles() {
            try repository.recordUncatalogedFinding(kind: .unexpectedTemporaryFile,observedPath: "staging/unknown.partial",quarantinePath: quarantinePath,detectedAt: recoveredAt)
        }
        let references = try repository.chunkCatalogReferences()
        let catalogByPath = Dictionary(uniqueKeysWithValues: references.map { ($0.relativePath, $0) })
        let filePaths = Set(try fileStore.finalizedRelativePaths())
        for path in filePaths where catalogByPath[path] == nil {
            let quarantinePath = try fileStore.quarantineFinalizedFile(relativePath: path)
            try repository.recordUncatalogedFinding(kind: .orphanFile,observedPath: path,quarantinePath: quarantinePath,detectedAt: recoveredAt)
        }
        for reference in references where reference.isAvailable && !filePaths.contains(reference.relativePath) {
            try repository.markChunkMissing(reference, detectedAt: recoveredAt)
        }
    }
}
