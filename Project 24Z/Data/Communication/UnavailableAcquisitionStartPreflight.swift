/// 認証済みDB、容量、鍵の開始条件が未接続なProduction構成を停止します。
struct UnavailableAcquisitionStartPreflight: AcquisitionStartPreflightChecking {
    /// Sessionを作らず開始不可を返します。
    /// - Throws: 常に`preflightBlocked`。
    func checkStartEligibility() async throws {
        throw AcquisitionStartFailure.preflightBlocked
    }
}
