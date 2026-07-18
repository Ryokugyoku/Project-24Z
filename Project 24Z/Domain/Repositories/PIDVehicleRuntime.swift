import Foundation

/// PID探索、Polling、車両識別に必要な型付き読取だけを実行するRuntime境界です。
nonisolated protocol PIDVehicleRuntime: Sendable {
    /// 承認済みCatalog定義をECU別に探索します。
    /// - Parameters:
    ///   - catalog: Version付きCatalog Snapshot。
    ///   - generation: 現在の接続Generation。
    ///   - attemptID: 現在の探索attempt UUID。
    /// - Returns: ECU別Rawを保持した終端Snapshot。
    /// - Throws: Catalog blocked、stale、timeoutまたはTransport失敗。
    func discoverSupport(
        catalog: PIDCatalogSnapshot,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) async throws -> PIDSupportSnapshot

    /// 実証済みbatch能力がある候補だけをbatchで実行します。
    /// - Parameters:
    ///   - identities: 同一ECUの型付きIdentity集合。
    ///   - generation: 現在の接続Generation。
    /// - Returns: Rawを保持したbatch結果。
    /// - Throws: capability拒否、timeoutまたはTransport失敗。
    func pollBatch(
        identities: [PIDSignalIdentity],
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse

    /// 一つのPID／ECUをsingle Requestで実行します。
    /// - Parameters:
    ///   - identity: 型付きPID／ECU Identity。
    ///   - generation: 現在の接続Generation。
    /// - Returns: Rawを保持したsingle結果。
    /// - Throws: timeoutまたはTransport失敗。
    func pollSingle(
        identity: PIDSignalIdentity,
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse
}
