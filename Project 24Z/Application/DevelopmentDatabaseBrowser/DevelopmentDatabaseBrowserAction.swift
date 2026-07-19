#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 開発専用Database Browserが受理する読取専用Actionです。
nonisolated enum DevelopmentDatabaseBrowserAction: Equatable, Sendable {
    case loadSources
    case selectSource(DevelopmentDatabaseSource)
    case selectTarget(DevelopmentDatabaseTarget)
    case loadNextPage
    case refresh
    case cancelLoading
    case openCell(rowID: Int, columnIndex: Int)
    case closeCell
}
#endif
