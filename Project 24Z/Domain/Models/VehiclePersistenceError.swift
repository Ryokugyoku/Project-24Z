import Foundation

/// 機密値を含まず、車両永続化を安全に停止する安定エラーです。
enum VehiclePersistenceError: Error, Equatable, Sendable {
    /// 入力Snapshotまたは暗号済み入力が設計契約を満たしません。
    case invalidRequest
    /// user scopeまたはDigest鍵VersionがDBと一致しません。
    case scopeMismatch
    /// Unique制約または期待Revisionとの競合です。
    case conflict
    /// 既存接続Snapshotと再試行要求が一致しません。
    case idempotencyConflict
    /// DBが利用できないため処理を非破壊で停止しました。
    case unavailable
}
