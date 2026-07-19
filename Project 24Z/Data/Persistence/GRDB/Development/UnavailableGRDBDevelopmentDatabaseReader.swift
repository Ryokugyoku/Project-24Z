#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 認証済みGRDB Store未接続時に元DBを変更せず利用不可を返します。
struct UnavailableGRDBDevelopmentDatabaseReader: DevelopmentDatabaseReading {
    /// GRDB sourceを担当します。
    let source = DevelopmentDatabaseSource.grdb

    /// tableを捏造せず利用不可を返します。
    /// - Returns: 戻りません。
    /// - Throws: 常に`unavailable`。
    func availableTargets() async throws -> [DevelopmentDatabaseTarget] { throw ConnectionSettingsError.unavailable }

    /// pageを読まず利用不可を返します。
    /// - Parameters:
    ///   - target: 読まないtarget。
    ///   - offset: 使用しないoffset。
    ///   - limit: 使用しないlimit。
    /// - Returns: 戻りません。
    /// - Throws: 常に`unavailable`。
    func readPage(target: DevelopmentDatabaseTarget, offset: Int, limit: Int) async throws -> DevelopmentDatabasePage { throw ConnectionSettingsError.unavailable }
}
#endif
