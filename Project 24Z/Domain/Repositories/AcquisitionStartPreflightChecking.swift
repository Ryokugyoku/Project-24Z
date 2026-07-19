/// Sessionを作らずDB、容量、鍵の開始条件を検査する能力です。
protocol AcquisitionStartPreflightChecking: Sendable {
    /// 永続化開始条件だけを検査します。
    /// - Throws: 利用不能理由に対応する`AcquisitionStartFailure`。
    func checkStartEligibility() async throws
}
