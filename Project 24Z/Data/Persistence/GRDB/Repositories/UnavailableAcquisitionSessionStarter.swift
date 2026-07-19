import Foundation

/// 認証済みAcquisition Store未接続時に空Session作成を拒否します。
struct UnavailableAcquisitionSessionStarter: AcquisitionSessionStarting {
    /// Sessionを作らず失敗します。
    /// - Parameters:
    ///   - scope: 使用しないscope。
    ///   - primary: 使用しないPrimary。
    ///   - secondary: 使用しないSecondary。
    ///   - startedAt: 使用しない日時。
    /// - Returns: 戻りません。
    /// - Throws: 常に`sessionCommitFailed`。
    func startSession(in scope: LocalDeviceScope, primary: PreparedAdapterConnection, secondary: PreparedAdapterConnection?, startedAt: Date) async throws -> UUID {
        throw AcquisitionStartFailure.sessionCommitFailed
    }
}
