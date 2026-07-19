import Foundation

/// 接続せずに探索された、端末ローカルのAdapter到達候補です。
nonisolated struct ConnectionEndpointCandidate: Equatable, Hashable, Sendable {
    /// 候補を端末内で比較するための不可逆な32-byte識別値です。
    let endpointDigest: Data

    /// 通常画面へ表示できる非機密名です。
    let displayName: String

    /// BLE、Classic、USB等を混同しないTransport種別です。
    let transportKind: TransportEndpoint.Kind

    /// 候補を検証し、不正な表示値やDigestを拒否します。
    /// - Parameters:
    ///   - endpointDigest: Endpoint identifierからData層で生成した32-byte Digest。
    ///   - displayName: 秘密IDを含まない表示名。
    ///   - transportKind: EndpointのTransport種別。
    /// - Throws: 値が保存契約を満たさない場合の`ConnectionSettingsError.invalidCandidate`。
    init(endpointDigest: Data, displayName: String, transportKind: TransportEndpoint.Kind) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpointDigest.count == 32, (1...128).contains(trimmedName.count) else {
            throw ConnectionSettingsError.invalidCandidate
        }
        self.endpointDigest = endpointDigest
        self.displayName = trimmedName
        self.transportKind = transportKind
    }
}
