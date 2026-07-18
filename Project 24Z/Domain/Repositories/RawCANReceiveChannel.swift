/// Secondaryからの車両bus送信能力を持たないRaw CAN受信専用境界です。
nonisolated protocol RawCANReceiveChannel: Sendable {
    /// 安全証拠とallowlistが成立した場合だけmonitorを開始します。
    /// - Parameter configuration: command bytesを含まない安全設定。
    /// - Throws: safety未確認またはTransport失敗。
    func startListening(configuration: RawCANListenConfiguration) async throws

    /// 次の受信Eventを返します。
    /// - Returns: Rawを保持したEvent。停止後は`nil`。
    func nextEvent() async -> RawCANEvent?

    /// allowlist済み停止操作だけを試みて受信を終了します。
    func stopListening() async
}
