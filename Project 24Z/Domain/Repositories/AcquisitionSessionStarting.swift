import Foundation

/// Stream集合確定後にSession、Stream、Clock Epochを一transactionで作る能力です。
protocol AcquisitionSessionStarting: Sendable {
    /// Session開始目録をcommitします。
    /// - Parameters:
    ///   - scope: 認証済みUserと端末境界。
    ///   - primary: 準備済みPrimary。
    ///   - secondary: 利用者確認後に採用する準備済みSecondary。PIDのみなら`nil`。
    ///   - startedAt: Session開始監査日時。
    /// - Returns: commit済みSession ID。
    /// - Throws: transactionがrollbackされた場合の安定失敗。
    func startSession(
        in scope: LocalDeviceScope,
        primary: PreparedAdapterConnection,
        secondary: PreparedAdapterConnection?,
        startedAt: Date
    ) async throws -> UUID
}
