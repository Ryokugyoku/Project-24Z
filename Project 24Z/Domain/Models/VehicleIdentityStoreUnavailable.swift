import Foundation

/// DBを自動削除・置換せず停止した理由を機密情報なしで伝える値です。
struct VehicleIdentityStoreUnavailable: Error, Equatable, Sendable {
    /// 利用不能の安定分類です。
    enum Reason: Equatable, Sendable {
        /// DBを開けませんでした。
        case openFailed
        /// このバイナリが知らないMigration Versionです。
        case unknownVersion
        /// SQLite整合性検査が失敗しました。
        case corrupted
        /// DBのユーザースコープが期待値と異なります。
        case scopeMismatch
        /// Migrationがtransactionごと失敗しました。
        case migrationFailed
    }

    /// UIや保護された診断経路で照合するランダムIDです。
    let diagnosticID: UUID
    /// 機密値を含まない利用不能分類です。
    let reason: Reason
}
