/// Chunk保存領域で検出した安定した不整合分類です。
enum StorageIntegrityFindingKind: String, Sendable {
    case orphanFile = "orphan_file"
    case missingFile = "missing_file"
    case unexpectedTemporaryFile = "unexpected_temporary_file"
}
