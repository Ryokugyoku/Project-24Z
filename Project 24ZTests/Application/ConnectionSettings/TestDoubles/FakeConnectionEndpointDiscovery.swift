@testable import Project_24Z

/// 接続能力を持たない候補探索Fakeです。
final class FakeConnectionEndpointDiscovery: ConnectionEndpointDiscovering, @unchecked Sendable {
    /// 次の探索で返す候補です。
    var candidates: [ConnectionEndpointCandidate] = []

    /// 次の探索で投げるErrorです。
    var error: ConnectionSettingsError?

    /// 探索回数です。
    private(set) var discoveryCount = 0

    /// 取消し回数です。
    private(set) var cancellationCount = 0

    /// 接続せずfixture候補を返します。
    /// - Parameter transportKind: 呼出し確認用Transport。
    /// - Returns: fixture候補。
    /// - Throws: 設定済みError。
    func discoverCandidates(for transportKind: TransportEndpoint.Kind) async throws -> [ConnectionEndpointCandidate] {
        discoveryCount += 1
        if let error { throw error }
        return candidates.filter { $0.transportKind == transportKind }
    }

    /// 取消し回数を記録します。
    func cancelDiscovery() async { cancellationCount += 1 }
}
