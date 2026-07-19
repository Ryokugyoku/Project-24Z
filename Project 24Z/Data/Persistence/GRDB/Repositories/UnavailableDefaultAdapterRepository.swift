import Foundation

/// 認証済みUser ScopeのGRDB Storeが未接続な構成を非破壊停止させます。
struct UnavailableDefaultAdapterRepository: DefaultAdapterRepository {
    /// 候補を返さず利用不可を通知します。
    /// - Parameter scope: DBへ使用しないscope。
    /// - Returns: 戻りません。
    /// - Throws: 常に`unavailable`。
    func activeCandidates(in scope: LocalDeviceScope) throws -> [CommunicationRole: DefaultAdapterCandidate] {
        throw ConnectionSettingsError.unavailable
    }

    /// 候補を保存しません。
    /// - Parameters:
    ///   - endpoint: 保存しない候補。
    ///   - role: 保存しない役割。
    ///   - scope: DBへ使用しないscope。
    ///   - now: 使用しない日時。
    /// - Returns: 戻りません。
    /// - Throws: 常に`unavailable`。
    func setDefault(endpoint: ConnectionEndpointCandidate, role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws -> DefaultAdapterCandidate {
        throw ConnectionSettingsError.unavailable
    }

    /// 候補を解除しません。
    /// - Parameters:
    ///   - role: 解除しない役割。
    ///   - scope: DBへ使用しないscope。
    ///   - now: 使用しない日時。
    /// - Throws: 常に`unavailable`。
    func clearDefault(role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws {
        throw ConnectionSettingsError.unavailable
    }

    /// bindingを読みません。
    /// - Parameters:
    ///   - candidateID: 使用しない候補ID。
    ///   - scope: DBへ使用しないscope。
    /// - Returns: 戻りません。
    /// - Throws: 常に`unavailable`。
    func verifiedBinding(candidateID: UUID, in scope: LocalDeviceScope) throws -> VerifiedAdapterBinding? {
        throw ConnectionSettingsError.unavailable
    }

    /// bindingを保存しません。
    /// - Parameter binding: 保存しないbinding。
    /// - Throws: 常に`unavailable`。
    func saveVerifiedBinding(_ binding: VerifiedAdapterBinding) throws {
        throw ConnectionSettingsError.unavailable
    }
}
