/// file保存段階へテスト可能な失敗を注入する境界です。
protocol ChunkFilePersistenceFailureInjecting: Sendable {
    /// 指定段階で失敗させる場合にthrowします。
    func check(_ fault: ChunkFilePersistenceFault) throws
}

/// Productionで失敗を注入しない既定実装です。
struct NoChunkFilePersistenceFailureInjector: ChunkFilePersistenceFailureInjecting {
    /// 副作用のないInjectorを構成します。
    init() {}

    /// どの段階でも成功します。
    /// - Parameter fault: 現在段階。
    func check(_ fault: ChunkFilePersistenceFault) throws {}
}
