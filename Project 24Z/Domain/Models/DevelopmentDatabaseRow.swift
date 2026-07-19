#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 開発専用Browserの一表示行です。表示番号はDB Primary Keyではありません。
nonisolated struct DevelopmentDatabaseRow: Equatable, Sendable, Identifiable {
    /// page内で安定する表示IDです。
    let id: Int

    /// 列順と一致する保存値です。
    let values: [DevelopmentDatabaseValue]
}
#endif
