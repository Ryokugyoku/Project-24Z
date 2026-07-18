/// Transport受信をChunk pipelineへ渡す境界です。受理を保存済みACKとして扱いません。
nonisolated protocol AcquisitionEventSink: Sendable {
    /// Eventを有界queueへ受理します。
    /// - Parameter event: 現在Generationで検証済みの受信Event。
    /// - Throws: 保存pipelineが受理不能な場合。既存データは削除しません。
    func accept(_ event: CommunicationRuntimeEvent) async throws
}
