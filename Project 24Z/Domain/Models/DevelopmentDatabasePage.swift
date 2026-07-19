#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
/// 固定上限付きread transaction一回分の開発専用pageです。
nonisolated struct DevelopmentDatabasePage: Equatable, Sendable {
    /// 対象列metadataです。
    let columns: [DevelopmentDatabaseColumn]

    /// page内の行です。
    let rows: [DevelopmentDatabaseRow]

    /// 読込開始offsetです。
    let offset: Int

    /// 対象tableの読込時点総行数です。
    let totalRowCount: Int

    /// 次pageが存在するかを示します。
    let hasNextPage: Bool

    /// page間の厳密Snapshotを保証しない旨です。
    let orderingNotice: String?
}
#endif
