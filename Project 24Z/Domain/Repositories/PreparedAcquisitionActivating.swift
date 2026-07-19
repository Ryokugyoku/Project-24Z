import Foundation

/// Session commit後だけPID取得とRaw CAN受信を開始する能力です。
protocol PreparedAcquisitionActivating: Sendable {
    /// commit済みSessionの取得Runtimeを開始します。
    /// - Parameters:
    ///   - sessionID: commit済みSession ID。
    ///   - primary: PID取得用Primary接続。
    ///   - secondary: Raw CAN receive-only用Secondary接続。
    /// - Throws: commit後障害として保持・終端すべき安定失敗。
    func activate(
        sessionID: UUID,
        primary: PreparedAdapterConnection,
        secondary: PreparedAdapterConnection?
    ) async throws
}
