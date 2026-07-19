import Foundation

/// 端末別・役割別の既定候補と確認済みbindingを保存する能力です。
protocol DefaultAdapterRepository {
    /// 指定端末のPrimary／Secondary既定候補を読みます。
    /// - Parameter scope: 認証済みUserとローカル端末の境界。
    /// - Returns: Activeな候補だけを役割別に返します。
    /// - Throws: Storeが安全に利用できない場合の安定エラー。
    func activeCandidates(in scope: LocalDeviceScope) throws -> [CommunicationRole: DefaultAdapterCandidate]

    /// 候補を役割のActive既定値として冪等保存します。
    /// - Parameters:
    ///   - endpoint: 接続せず探索したEndpoint候補。
    ///   - role: 保存先の固定役割。
    ///   - scope: 認証済みUserとローカル端末の境界。
    ///   - now: 監査日時。
    /// - Returns: DBから読戻した確定済み候補。
    /// - Throws: 重複役割、scope不一致、Store unavailable等。
    func setDefault(
        endpoint: ConnectionEndpointCandidate,
        role: CommunicationRole,
        in scope: LocalDeviceScope,
        now: Date
    ) throws -> DefaultAdapterCandidate

    /// 対象役割のActive候補を解除し、履歴と過去Sessionを保持します。
    /// - Parameters:
    ///   - role: 解除する役割。
    ///   - scope: 認証済みUserとローカル端末の境界。
    ///   - now: 監査日時。
    /// - Throws: scope不一致、Store unavailable等。
    func clearDefault(role: CommunicationRole, in scope: LocalDeviceScope, now: Date) throws

    /// 接続後に確認済みのIdentity bindingを読みます。
    /// - Parameters:
    ///   - candidateID: 対象候補ID。
    ///   - scope: 認証済みUserとローカル端末の境界。
    /// - Returns: Active binding。未確認なら`nil`。
    /// - Throws: scope不一致、Store unavailable等。
    func verifiedBinding(candidateID: UUID, in scope: LocalDeviceScope) throws -> VerifiedAdapterBinding?

    /// 接続後に承認済み規則で確認したIdentity bindingを冪等保存します。
    /// - Parameter binding: 不明Identityを含まない確認済みbinding。
    /// - Throws: 候補scope不一致、同一物理Adapterの役割重複、Store unavailable等。
    func saveVerifiedBinding(_ binding: VerifiedAdapterBinding) throws
}
