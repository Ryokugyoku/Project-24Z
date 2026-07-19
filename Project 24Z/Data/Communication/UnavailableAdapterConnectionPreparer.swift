/// Adapter／firmware／allowlist Hard Gate未達時に接続準備を拒否します。
struct UnavailableAdapterConnectionPreparer: AdapterConnectionPreparing {
    /// Transportへ接続せず利用不可を返します。
    /// - Parameters:
    ///   - candidate: 接続しない候補。
    ///   - binding: 使用しないbinding。
    ///   - generation: 使用しないGeneration。
    /// - Returns: 戻りません。
    /// - Throws: 常に`adapterUnsupported`。
    func prepare(candidate: DefaultAdapterCandidate, binding: VerifiedAdapterBinding?, generation: ConnectionGeneration) async throws -> PreparedAdapterConnection {
        throw AcquisitionStartFailure.adapterUnsupported
    }

    /// 接続資源を所有しないため何もしません。
    func close() async {}
}
