import Foundation
@testable import Project_24Z

/// Applicationテスト用の端末scope分離Repositoryです。
final class InMemoryDefaultAdapterRepository: DefaultAdapterRepository {
    /// scopeとrole別のActive候補です。
    private var candidates: [LocalDeviceScope: [CommunicationRole: DefaultAdapterCandidate]] = [:]

    /// 候補ID別bindingです。
    private var bindings: [UUID: VerifiedAdapterBinding] = [:]

    /// 保存Action回数です。
    private(set) var setCallCount = 0

    /// 指定scopeの候補を返します。
    /// - Parameter scope: 端末scope。
    /// - Returns: Active候補。
    func activeCandidates(in scope: LocalDeviceScope) throws -> [CommunicationRole: DefaultAdapterCandidate] {
        candidates[scope, default: [:]]
    }

    /// 重複Endpointを拒否して候補を保存します。
    /// - Parameters:
    ///   - endpoint: 保存候補。
    ///   - role: 対象役割。
    ///   - scope: 端末scope。
    ///   - now: 監査日時。
    /// - Returns: 確定候補。
    /// - Throws: 反対役割と同じEndpointなら重複Error。
    func setDefault(endpoint: ConnectionEndpointCandidate, role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws -> DefaultAdapterCandidate {
        setCallCount += 1
        if let existing = candidates[scope]?[role], existing.endpoint == endpoint { return existing }
        guard !candidates[scope, default: [:]].values.contains(where: { $0.role != role && $0.endpoint.endpointDigest == endpoint.endpointDigest }) else {
            throw ConnectionSettingsError.duplicateRoleCandidate
        }
        let value = DefaultAdapterCandidate(candidateID: UUID(), scope: scope, role: role, endpoint: endpoint, revision: 1, createdAt: now, updatedAt: now)
        candidates[scope, default: [:]][role] = value
        return value
    }

    /// 対象役割だけを解除します。
    /// - Parameters:
    ///   - role: 対象役割。
    ///   - scope: 端末scope。
    ///   - now: 使用しない監査日時。
    func clearDefault(role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws {
        candidates[scope]?[role] = nil
    }

    /// 候補のbindingを返します。
    /// - Parameters:
    ///   - candidateID: 候補ID。
    ///   - scope: scope照合用境界。
    /// - Returns: 同じscopeのbinding。
    func verifiedBinding(candidateID: UUID, in scope: LocalDeviceScope) throws -> VerifiedAdapterBinding? {
        guard bindings[candidateID]?.scope == scope else { return nil }
        return bindings[candidateID]
    }

    /// bindingを保存します。
    /// - Parameter binding: 確認済みbinding。
    func saveVerifiedBinding(_ binding: VerifiedAdapterBinding) throws {
        bindings[binding.candidateID] = binding
    }
}
