import Foundation

/// 永続化方式に依存しない登録車両の状態です。
struct VehicleIdentity: Equatable, Sendable {
    /// 車両のライフサイクル状態です。
    enum Lifecycle: String, Equatable, Sendable {
        /// 通常利用できる車両です。
        case active
        /// 履歴を残したまま通常一覧から分離した車両です。
        case archived
    }

    /// 所有するユーザースコープです。
    let userScopeID: UUID
    /// VIN等とは独立した内部車両IDです。
    let vehicleID: UUID
    /// 暗号化済みの任意表示名です。
    let encryptedDisplayName: EncryptedVehicleValue?
    /// 現在のライフサイクル状態です。
    let lifecycle: Lifecycle
    /// 行全体のRevisionです。
    let recordRevision: Int
    /// 表示名フィールドのRevisionです。
    let displayNameRevision: Int
    /// ライフサイクルフィールドのRevisionです。
    let lifecycleRevision: Int
    /// アーカイブ日時です。activeではnilです。
    let archivedAt: Date?
    /// 作成日時です。
    let createdAt: Date
    /// 最終更新日時です。
    let updatedAt: Date
}
