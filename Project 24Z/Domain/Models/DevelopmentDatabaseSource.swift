#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 開発専用Browserが区別して表示する保存方式です。
nonisolated enum DevelopmentDatabaseSource: String, CaseIterable, Equatable, Hashable, Sendable {
    case grdb = "GRDB"
    case swiftData = "SwiftData"
}
#endif
