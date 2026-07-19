#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 開発専用Browserが読取対象として列挙したtableまたは論理データセットです。
nonisolated struct DevelopmentDatabaseTarget: Equatable, Hashable, Sendable {
    /// 保存方式を混同しないsourceです。
    let source: DevelopmentDatabaseSource

    /// schema discoveryまたは明示Adapterが返した対象名です。
    let name: String
}
#endif
