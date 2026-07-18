import Foundation

/// PID Hard Gate未達時に型付きRuntime要求を送信前に拒否するProduction Adapterです。
nonisolated struct UnavailablePIDVehicleRuntime: PIDVehicleRuntime, Sendable {
    /// Production用の送信不能Runtimeを構成します。
    init() {}

    /// 未検証CatalogをTransportへ送らず拒否します。
    /// - Parameters:
    ///   - catalog: 送信しないCatalog Snapshot。
    ///   - generation: 送信しない接続Generation。
    ///   - attemptID: 送信しない探索attempt UUID。
    /// - Returns: この実装はSnapshotを返しません。
    /// - Throws: 常に`commandNotAllowlisted`。
    func discoverSupport(
        catalog: PIDCatalogSnapshot,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) async throws -> PIDSupportSnapshot {
        throw CommunicationRuntimeError.commandNotAllowlisted
    }

    /// 未検証batch要求をTransportへ送らず拒否します。
    /// - Parameters:
    ///   - identities: 送信しないPID Identity集合。
    ///   - generation: 送信しない接続Generation。
    /// - Returns: この実装は応答を返しません。
    /// - Throws: 常に`commandNotAllowlisted`。
    func pollBatch(
        identities: [PIDSignalIdentity],
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse {
        throw CommunicationRuntimeError.commandNotAllowlisted
    }

    /// 未検証single要求をTransportへ送らず拒否します。
    /// - Parameters:
    ///   - identity: 送信しないPID Identity。
    ///   - generation: 送信しない接続Generation。
    /// - Returns: この実装は応答を返しません。
    /// - Throws: 常に`commandNotAllowlisted`。
    func pollSingle(
        identity: PIDSignalIdentity,
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse {
        throw CommunicationRuntimeError.commandNotAllowlisted
    }
}
