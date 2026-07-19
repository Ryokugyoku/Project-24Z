#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 編集能力を持たない開発専用Database読取境界です。
protocol DevelopmentDatabaseReading: Sendable {
    /// このAdapterが担当する保存方式です。
    var source: DevelopmentDatabaseSource { get }

    /// 読取可能なtable／論理データセットを列挙します。
    /// - Returns: 任意SQL入力を含まない対象一覧。
    /// - Throws: Store unavailable、scope不一致、schema read失敗。
    func availableTargets() async throws -> [DevelopmentDatabaseTarget]

    /// 一回の短いread transactionで固定上限pageを読みます。
    /// - Parameters:
    ///   - target: 直前の列挙結果と一致する対象。
    ///   - offset: 0以上の開始位置。
    ///   - limit: 技術境界が許可する固定上限以下の件数。
    /// - Returns: storage classを保ったpage。
    /// - Throws: 対象不一致、schema変更、読取失敗。
    func readPage(target: DevelopmentDatabaseTarget, offset: Int, limit: Int) async throws -> DevelopmentDatabasePage
}
#endif
