import Foundation

/// PID取得とRaw CAN受信を停止し、旧Transport callbackと接続資源を順序付きで終了する能力です。
nonisolated protocol AcquisitionRuntimeStopping: Sendable {
    /// 新しいPID要求の発行を停止します。
    /// - Parameter sessionID: 対象Session ID。
    /// - Throws: 停止状態を確認できない場合。
    func stopPIDRequests(sessionID: UUID) async throws

    /// Raw CAN monitorと新規受信を停止します。
    /// - Parameter sessionID: 対象Session ID。
    /// - Throws: 停止状態を確認できない場合。
    func stopRawCANReception(sessionID: UUID) async throws

    /// Generationを失効させ、以後の旧callbackを受理しません。
    /// - Parameter sessionID: 対象Session ID。
    func invalidateCallbacks(sessionID: UUID) async

    /// Stream／Session終端transactionの後にTransport資源を閉じます。
    ///
    /// Generation失効後の資源解放であり、旧callbackを再び有効化しません。
    /// - Parameter sessionID: 対象Session ID。
    func closeTransport(sessionID: UUID) async
}
