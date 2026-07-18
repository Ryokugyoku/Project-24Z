import Foundation

/// Catalog Hard GateとGeneration／attemptを検証してsupport探索を接続するactorです。
actor PIDSupportDiscoveryCoordinator {
    /// 探索を開始できない安定理由です。
    enum Error: Swift.Error, Equatable {
        case catalogBlocked
        case staleGeneration
        case staleAttempt
        case incompatibleSnapshot
    }

    private let runtime: any PIDVehicleRuntime
    private var currentGeneration: ConnectionGeneration?
    private var currentAttemptID: UUID?

    /// 型付きRuntimeを注入します。
    /// - Parameter runtime: PID／車両識別Runtime境界。
    init(runtime: any PIDVehicleRuntime) {
        self.runtime = runtime
    }

    /// current tokenを固定して承認済みCatalogだけを探索します。
    /// - Parameters:
    ///   - catalog: Version付きCatalog。
    ///   - generation: 現在接続Generation。
    ///   - attemptID: 新しい探索attempt UUID。
    /// - Returns: tokenとVersionを再確認した終端Snapshot。
    /// - Throws: Hard Gate、stale、Runtime失敗。
    func discover(
        catalog: PIDCatalogSnapshot,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) async throws -> PIDSupportSnapshot {
        guard catalog.availability == .approved, !catalog.approvedEntries.isEmpty else {
            throw Error.catalogBlocked
        }
        currentGeneration = generation
        currentAttemptID = attemptID
        let result = try await runtime.discoverSupport(
            catalog: catalog,
            generation: generation,
            attemptID: attemptID
        )
        guard currentGeneration == generation else { throw Error.staleGeneration }
        guard currentAttemptID == attemptID else { throw Error.staleAttempt }
        guard result.connectionGeneration == generation,
              result.catalogVersion == catalog.version else {
            throw Error.incompatibleSnapshot
        }
        return result
    }

    /// pause、stop、再接続時に現在結果をstaleにします。
    func invalidate() {
        currentGeneration = nil
        currentAttemptID = nil
    }
}
