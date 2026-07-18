import Foundation

/// 不透明Chunk bytesを同一Volume上でimmutable fileとして確定します。
protocol ImmutableChunkFileStore {
    /// staging、同期、読戻し、atomic rename、最終検証を行います。
    func finalize(_ chunk: PreparedAcquisitionChunk) throws -> FinalizedChunkFile
    /// 再起動時に未確定stagingを正常領域へ公開せず隔離します。
    func quarantineStagingFiles() throws -> [String]
    /// 正常領域に存在するChunk相対pathをsymlinkを辿らず列挙します。
    func finalizedRelativePaths() throws -> [String]
    /// 曖昧な孤立fileを削除せずquarantineへ移します。
    func quarantineFinalizedFile(relativePath: String) throws -> String
}
