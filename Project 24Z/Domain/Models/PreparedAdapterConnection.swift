/// Session commit前の検査を全て通過した一役割の接続です。
nonisolated struct PreparedAdapterConnection: Equatable, Sendable {
    /// 準備済みの固定役割です。
    let role: CommunicationRole

    /// 確認済み物理Adapter参照です。
    let adapterReference: AdapterReference

    /// stale callbackを拒否する接続Generationです。
    let generation: ConnectionGeneration
}
