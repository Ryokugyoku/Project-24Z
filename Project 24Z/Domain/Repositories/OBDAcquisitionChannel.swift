/// Primary Adapterだけが利用する読取専用OBD request境界です。
nonisolated protocol OBDAcquisitionChannel: Sendable {
    /// 許可済みの読取用途を一件実行します。
    /// - Parameters:
    ///   - request: 書込、消去、ECU resetを表現できないOBD Request。
    ///   - timeout: 呼出側Policyが決めたdeadline。
    /// - Returns: Rawを保持したELM応答。
    /// - Throws: allowlist拒否、timeout境界喪失、Transport失敗。
    func request(_ request: OBDDiagnosticRequest, timeout: Duration) async throws -> ELMResponseEnvelope
}
