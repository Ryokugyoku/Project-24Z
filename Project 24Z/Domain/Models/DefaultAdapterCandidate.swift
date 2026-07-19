import Foundation

/// 役割別に確定保存された端末ローカルの既定Endpoint候補です。
nonisolated struct DefaultAdapterCandidate: Equatable, Sendable {
    /// 監査履歴内で不変の設定IDです。
    let candidateID: UUID

    /// 設定を所有するUser・端末境界です。
    let scope: LocalDeviceScope

    /// PrimaryまたはSecondaryの固定役割です。
    let role: CommunicationRole

    /// 接続前のEndpoint候補です。
    let endpoint: ConnectionEndpointCandidate

    /// 楽観的更新に使うRevisionです。
    let revision: Int

    /// 初回確定日時です。
    let createdAt: Date

    /// 最終確定日時です。
    let updatedAt: Date
}
