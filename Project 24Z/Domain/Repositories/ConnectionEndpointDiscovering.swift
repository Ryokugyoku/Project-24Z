/// 設定画面のLifecycle内だけでEndpoint候補を探索する能力です。
protocol ConnectionEndpointDiscovering: Sendable {
    /// 対象Transportの権限を利用者操作に応じて要求し、探索を開始します。
    /// - Parameter transportKind: BLE、Classic、USB等を分離したTransport種別。
    /// - Returns: 接続やIdentity probeを行っていない候補一覧。
    /// - Throws: 権限、非対応、探索失敗の安定エラー。
    func discoverCandidates(for transportKind: TransportEndpoint.Kind) async throws -> [ConnectionEndpointCandidate]

    /// 現在の探索を取消し、設定画面外へtaskを残しません。
    func cancelDiscovery() async
}
