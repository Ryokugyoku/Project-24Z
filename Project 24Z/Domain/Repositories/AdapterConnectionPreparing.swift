/// Endpoint再探索、接続、Identity、firmware、能力、allowlistを準備する能力です。
protocol AdapterConnectionPreparing: Sendable {
    /// 一役割をSession作成前まで準備します。
    /// - Parameters:
    ///   - candidate: 保存済みEndpoint候補。
    ///   - binding: 過去に確認済みのIdentity binding。初回は`nil`。
    ///   - generation: 今回の新Connection Generation。
    /// - Returns: 全Hard Gateを通過した準備済み接続。
    /// - Throws: Identity、Transport、allowlist等の安定失敗。
    func prepare(
        candidate: DefaultAdapterCandidate,
        binding: VerifiedAdapterBinding?,
        generation: ConnectionGeneration
    ) async throws -> PreparedAdapterConnection

    /// 一部成功を含む全Transportを閉じます。
    func close() async
}
