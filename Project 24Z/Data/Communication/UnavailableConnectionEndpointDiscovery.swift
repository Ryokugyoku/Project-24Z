/// 対応Adapter・firmware・TransportのHard Gate未達時に探索を拒否します。
struct UnavailableConnectionEndpointDiscovery: ConnectionEndpointDiscovering {
    /// 候補や権限を推測せず利用不可を返します。
    /// - Parameter transportKind: 有効化しないTransport。
    /// - Returns: 戻りません。
    /// - Throws: 常に`transportUnsupported`。
    func discoverCandidates(for transportKind: TransportEndpoint.Kind) async throws -> [ConnectionEndpointCandidate] {
        throw ConnectionSettingsError.transportUnsupported
    }

    /// 探索資源を所有しないため何もしません。
    func cancelDiscovery() async {}
}
