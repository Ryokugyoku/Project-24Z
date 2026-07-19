#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Foundation

/// 開発専用Database Browserの読込段階です。
nonisolated enum DevelopmentDatabaseBrowserLoadState: Equatable, Sendable {
    case idle
    case loadingSchema
    case loadingTable
    case loadingNextPage
    case loaded
    case cancelled
    case unavailable(String)
}

/// cell詳細sheetへ渡す全保存値です。
nonisolated struct DevelopmentDatabaseCellDetail: Equatable, Sendable {
    /// 表示行番号です。
    let rowNumber: Int
    /// 列名です。
    let columnName: String
    /// storage class名です。
    let storageClassName: String
    /// NULLまたは完全値です。
    let fullValue: String
}

/// Platform非依存の開発専用Database Browser Stateです。
nonisolated struct DevelopmentDatabaseBrowserState: Equatable, Sendable {
    /// 利用可能な保存方式です。
    let sources: [DevelopmentDatabaseSource]
    /// 選択中sourceです。
    let selectedSource: DevelopmentDatabaseSource?
    /// 選択sourceのtable／datasetです。
    let targets: [DevelopmentDatabaseTarget]
    /// 選択中targetです。
    let selectedTarget: DevelopmentDatabaseTarget?
    /// 列metadataです。
    let columns: [DevelopmentDatabaseColumn]
    /// 読込済みpageを連結した行です。
    let rows: [DevelopmentDatabaseRow]
    /// 読込時点の総行数です。
    let totalRowCount: Int
    /// 次pageの有無です。
    let hasNextPage: Bool
    /// 最終更新日時です。
    let lastLoadedAt: Date?
    /// 現在読込状態です。
    let loadState: DevelopmentDatabaseBrowserLoadState
    /// page間Snapshotを保証しない説明です。
    let orderingNotice: String?
    /// 選択cell詳細です。
    let cellDetail: DevelopmentDatabaseCellDetail?

    /// 初期未選択状態です。
    static let initial = Self(sources: [], selectedSource: nil, targets: [], selectedTarget: nil, columns: [], rows: [], totalRowCount: 0, hasNextPage: false, lastLoadedAt: nil, loadState: .idle, orderingNotice: nil, cellDetail: nil)
}
#endif
