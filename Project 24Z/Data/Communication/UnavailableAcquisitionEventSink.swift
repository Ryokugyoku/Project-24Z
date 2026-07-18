/// Acquisition保存pipelineのProduction前提未達時にEvent受理を拒否するAdapterです。
nonisolated struct UnavailableAcquisitionEventSink: AcquisitionEventSink, Sendable {
    /// Production用の受理不能Sinkを構成します。
    init() {}

    /// Eventを保存済みまたはqueue受理済みとして扱わず拒否します。
    /// - Parameter event: 保存しないRuntime Event。
    /// - Throws: 常に`storageUnavailable`。
    func accept(_ event: CommunicationRuntimeEvent) async throws {
        throw CommunicationRuntimeError.storageUnavailable
    }
}
