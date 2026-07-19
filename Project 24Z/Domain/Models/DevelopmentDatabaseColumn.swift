#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 開発専用Browserが表示する物理列または明示Application propertyです。
nonisolated struct DevelopmentDatabaseColumn: Equatable, Hashable, Sendable {
    /// 保存済み列名です。
    let name: String

    /// SQLite宣言型またはApplication property型です。
    let declaredType: String

    /// Primary Key内の順序です。0は非Primary Keyです。
    let primaryKeyOrdinal: Int

    /// hidden／generated列なら`true`です。
    let isHidden: Bool
}
#endif
