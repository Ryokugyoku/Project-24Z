/// 一接続試行だけで有効なprocess-local世代番号です。
nonisolated struct ConnectionGeneration: Equatable, Hashable, Comparable, Sendable {
    let value: UInt64

    /// 世代番号の大小を比較します。
    /// - Parameters:
    ///   - lhs: 左辺の世代番号。
    ///   - rhs: 右辺の世代番号。
    /// - Returns: 左辺が古い場合は`true`。
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}
