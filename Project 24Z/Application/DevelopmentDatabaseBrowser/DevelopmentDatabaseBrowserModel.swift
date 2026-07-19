#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Combine
import Foundation

/// schema選択、固定page読込、stale拒否を調停する開発専用Application Modelです。
@MainActor
final class DevelopmentDatabaseBrowserModel: ObservableObject {
    /// Platformが描画する読取専用Stateです。
    @Published private(set) var state: DevelopmentDatabaseBrowserState = .initial

    /// source別の読取Adapterです。
    private let readers: [DevelopmentDatabaseSource: any DevelopmentDatabaseReading]

    /// 一回に読む技術上限です。
    private let pageSize: Int

    /// stale完了を拒否するGenerationです。
    private var generation = 0

    /// 読取Adapter群を構成します。
    /// - Parameters:
    ///   - readers: GRDBと明示SwiftData datasetの読取専用Adapter。
    ///   - pageSize: 実測で調整可能な固定page上限。
    init(readers: [any DevelopmentDatabaseReading], pageSize: Int = 100) {
        self.readers = Dictionary(uniqueKeysWithValues: readers.map { ($0.source, $0) })
        self.pageSize = max(1, min(pageSize, 500))
    }

    /// 読取専用Actionを実行します。
    /// - Parameter action: Platformから通知されたAction。
    func perform(_ action: DevelopmentDatabaseBrowserAction) async {
        switch action {
        case .loadSources:
            await loadSources()
        case .selectSource(let source):
            await selectSource(source)
        case .selectTarget(let target):
            await selectTarget(target)
        case .loadNextPage:
            await loadNextPage()
        case .refresh:
            if let target = state.selectedTarget { await selectTarget(target) }
        case .cancelLoading:
            generation += 1
            replace(loadState: .cancelled)
        case .openCell(let rowID, let columnIndex):
            openCell(rowID: rowID, columnIndex: columnIndex)
        case .closeCell:
            replace(cellDetail: nil)
        }
    }

    /// 利用可能sourceだけを公開します。
    private func loadSources() async {
        generation += 1
        state = .init(sources: readers.keys.sorted { $0.rawValue < $1.rawValue }, selectedSource: nil, targets: [], selectedTarget: nil, columns: [], rows: [], totalRowCount: 0, hasNextPage: false, lastLoadedAt: nil, loadState: .idle, orderingNotice: nil, cellDetail: nil)
    }

    /// sourceの対象一覧を再発見します。
    /// - Parameter source: 選択source。
    private func selectSource(_ source: DevelopmentDatabaseSource) async {
        let operation = nextGeneration()
        state = .init(sources: state.sources, selectedSource: source, targets: [], selectedTarget: nil, columns: [], rows: [], totalRowCount: 0, hasNextPage: false, lastLoadedAt: nil, loadState: .loadingSchema, orderingNotice: nil, cellDetail: nil)
        guard let reader = readers[source] else {
            replace(loadState: .unavailable("このデータソースは利用できません。"))
            return
        }
        do {
            let targets = try await reader.availableTargets()
            guard operation == generation else { return }
            state = .init(sources: state.sources, selectedSource: source, targets: targets.sorted { $0.name < $1.name }, selectedTarget: nil, columns: [], rows: [], totalRowCount: 0, hasNextPage: false, lastLoadedAt: Date(), loadState: .loaded, orderingNotice: nil, cellDetail: nil)
        } catch {
            guard operation == generation else { return }
            replace(loadState: .unavailable("Storeを読取専用で開けません。元データは変更していません。"))
        }
    }

    /// targetの最初のpageを読みます。
    /// - Parameter target: discovery済みtarget。
    private func selectTarget(_ target: DevelopmentDatabaseTarget) async {
        guard state.targets.contains(target), let reader = readers[target.source] else { return }
        let operation = nextGeneration()
        state = .init(sources: state.sources, selectedSource: target.source, targets: state.targets, selectedTarget: target, columns: [], rows: [], totalRowCount: 0, hasNextPage: false, lastLoadedAt: state.lastLoadedAt, loadState: .loadingTable, orderingNotice: nil, cellDetail: nil)
        do {
            let page = try await reader.readPage(target: target, offset: 0, limit: pageSize)
            guard operation == generation else { return }
            apply(page: page, appending: false)
        } catch {
            guard operation == generation else { return }
            replace(loadState: .unavailable("tableを読み取れません。schema変更またはStore状態を確認してください。"))
        }
    }

    /// 次pageを短い別transactionで読みます。
    private func loadNextPage() async {
        guard state.hasNextPage, let target = state.selectedTarget, let reader = readers[target.source] else { return }
        let operation = nextGeneration()
        replace(loadState: .loadingNextPage)
        do {
            let page = try await reader.readPage(target: target, offset: state.rows.count, limit: pageSize)
            guard operation == generation else { return }
            apply(page: page, appending: true)
        } catch {
            guard operation == generation else { return }
            replace(loadState: .unavailable("次のpageを読み取れません。"))
        }
    }

    /// pageを現在Stateへ反映します。
    /// - Parameters:
    ///   - page: 読込結果。
    ///   - appending: 既存行へ追加するか。
    private func apply(page: DevelopmentDatabasePage, appending: Bool) {
        state = .init(sources: state.sources, selectedSource: state.selectedSource, targets: state.targets, selectedTarget: state.selectedTarget, columns: page.columns, rows: appending ? state.rows + page.rows : page.rows, totalRowCount: page.totalRowCount, hasNextPage: page.hasNextPage, lastLoadedAt: Date(), loadState: .loaded, orderingNotice: page.orderingNotice, cellDetail: nil)
    }

    /// 読込済みcellの完全値をdetailへ公開します。
    /// - Parameters:
    ///   - rowID: 表示行ID。
    ///   - columnIndex: 列index。
    private func openCell(rowID: Int, columnIndex: Int) {
        guard let row = state.rows.first(where: { $0.id == rowID }), state.columns.indices.contains(columnIndex), row.values.indices.contains(columnIndex) else { return }
        let value = row.values[columnIndex]
        replace(cellDetail: .init(rowNumber: row.id + 1, columnName: state.columns[columnIndex].name, storageClassName: value.storageClassName, fullValue: value.detailText))
    }

    /// 新Generationを発行します。
    /// - Returns: 今回operationのGeneration。
    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    /// Stateの読込状態だけを置換します。
    /// - Parameter loadState: 新しい読込状態。
    private func replace(loadState: DevelopmentDatabaseBrowserLoadState) {
        state = .init(sources: state.sources, selectedSource: state.selectedSource, targets: state.targets, selectedTarget: state.selectedTarget, columns: state.columns, rows: state.rows, totalRowCount: state.totalRowCount, hasNextPage: state.hasNextPage, lastLoadedAt: state.lastLoadedAt, loadState: loadState, orderingNotice: state.orderingNotice, cellDetail: state.cellDetail)
    }

    /// Stateのcell詳細だけを置換します。
    /// - Parameter cellDetail: 新しい詳細または`nil`。
    private func replace(cellDetail: DevelopmentDatabaseCellDetail?) {
        state = .init(sources: state.sources, selectedSource: state.selectedSource, targets: state.targets, selectedTarget: state.selectedTarget, columns: state.columns, rows: state.rows, totalRowCount: state.totalRowCount, hasNextPage: state.hasNextPage, lastLoadedAt: state.lastLoadedAt, loadState: state.loadState, orderingNotice: state.orderingNotice, cellDetail: cellDetail)
    }
}
#endif
