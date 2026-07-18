import Foundation

/// 一Endpointへのbyte通信をPlatform固有実装から分離する能力です。
nonisolated protocol CommunicationTransport: Sendable {
    /// Endpointを開き、捕捉したGeneration付きcallbackを登録します。
    /// - Parameters:
    ///   - endpoint: ユーザーが明示選択した到達先。
    ///   - generation: 今回のprocess-local世代。
    ///   - eventHandler: Transport Eventの通知先。
    /// - Throws: Platform経路が未検証または接続不能の場合の安定エラー。
    func open(endpoint: TransportEndpoint, generation: ConnectionGeneration, eventHandler: @escaping @Sendable (TransportEvent) -> Void) async throws

    /// 現在GenerationのAdapterへbytesを書き込みます。
    /// - Parameters:
    ///   - bytes: Data層の型付きencoderが生成したbytes。
    ///   - generation: 書込対象の世代。
    /// - Throws: 接続断、stale世代、または書込失敗。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws

    /// callbackを止めて接続資源を解放します。
    func close() async
}
