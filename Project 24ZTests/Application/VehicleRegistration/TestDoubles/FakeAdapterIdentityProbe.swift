@testable import Project_24Z

/// 車両登録Modelへ固定Adapter identityを返すProbe Fakeです。
actor FakeAdapterIdentityProbe: AdapterIdentityProbing {
    private(set) var callCount = 0

    /// 固定identityを返し、呼出回数を記録します。
    /// - Returns: Runbookと一致する非機密fixture identity。
    func verifyApprovedAdapter() async throws -> VerifiedAdapterIdentity {
        callCount += 1
        return VerifiedAdapterIdentity(
            displayName: "OBDLink EX (EX101)",
            hardwareVersion: "OBDLink EX r2.7.1",
            firmwareVersion: "STN2232 v5.10.3"
        )
    }

    /// FakeはTransport資源を持たないため何もしません。
    func cancel() async {}

    /// 記録済み呼出回数を返します。
    /// - Returns: Probe呼出回数。
    func recordedCallCount() -> Int {
        callCount
    }
}
