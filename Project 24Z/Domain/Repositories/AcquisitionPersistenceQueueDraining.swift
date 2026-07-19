import Foundation

/// 受理済み保存queueをdrainし、確定可能ChunkをDurable ACKまで処理する能力です。
nonisolated protocol AcquisitionPersistenceQueueDraining: Sendable {
    /// 受理済みqueueを閉じ、確定可能な全Chunkを安全なfile先行順序で確定します。
    /// - Parameter sessionID: 対象Session ID。
    /// - Throws: 保存、検証、または目録commit失敗。既存Chunkは削除しません。
    func drainAndFinalizeChunks(sessionID: UUID) async throws
}
