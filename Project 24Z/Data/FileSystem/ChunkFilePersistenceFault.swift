/// Chunk file確定テストで注入できる安定した失敗位置です。
enum ChunkFilePersistenceFault: Hashable, Sendable {
    case afterStagingWrite
    case afterStagingSynchronize
    case afterRename
    case beforeFinalVerification
}
