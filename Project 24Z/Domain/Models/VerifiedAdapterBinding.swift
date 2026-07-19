import Foundation

/// 接続後の承認済みIdentity確認でだけ保存できる物理Adapter bindingです。
nonisolated struct VerifiedAdapterBinding: Equatable, Sendable {
    /// bindingの監査IDです。
    let bindingID: UUID

    /// binding対象の既定候補IDです。
    let candidateID: UUID

    /// 候補を所有する端末境界です。
    let scope: LocalDeviceScope

    /// 接続後に確認した物理Adapter参照の不可逆な32-byte Digestです。
    let adapterReferenceDigest: Data

    /// Identity規則のVersionです。
    let verificationVersion: String

    /// 確認日時です。
    let verifiedAt: Date

    /// 確認済みIdentity bindingを検証して生成します。
    /// - Parameters:
    ///   - bindingID: 監査ID。
    ///   - candidateID: 対象候補ID。
    ///   - scope: User・端末境界。
    ///   - adapterReferenceDigest: Identity規則が生成した32-byte Digest。
    ///   - verificationVersion: Identity規則Version。
    ///   - verifiedAt: 確認日時。
    /// - Throws: DigestまたはVersionが保存契約を満たさない場合の`invalidCandidate`。
    init(
        bindingID: UUID,
        candidateID: UUID,
        scope: LocalDeviceScope,
        adapterReferenceDigest: Data,
        verificationVersion: String,
        verifiedAt: Date
    ) throws {
        guard adapterReferenceDigest.count == 32, (1...64).contains(verificationVersion.count) else {
            throw ConnectionSettingsError.invalidCandidate
        }
        self.bindingID = bindingID
        self.candidateID = candidateID
        self.scope = scope
        self.adapterReferenceDigest = adapterReferenceDigest
        self.verificationVersion = verificationVersion
        self.verifiedAt = verifiedAt
    }
}
