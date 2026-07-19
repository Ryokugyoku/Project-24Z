#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Foundation
import SwiftData

/// SwiftData内部SQLiteを開かず、ItemだけをAPI経由で読む開発専用Adapterです。
@MainActor
final class SwiftDataItemDevelopmentDatabaseReader: DevelopmentDatabaseReading {
    /// SwiftData sourceを担当します。
    let source = DevelopmentDatabaseSource.swiftData

    /// fetchだけに使用するModelContextです。
    private let context: ModelContext

    /// 実Application ModelContainerから読取Contextを作ります。
    /// - Parameter container: Productionと同じSwiftData container。
    init(container: ModelContainer) { context = ModelContext(container) }

    /// 明示対応したItem datasetだけを返します。
    /// - Returns: `Item`一件のtarget一覧。
    func availableTargets() async throws -> [DevelopmentDatabaseTarget] {
        [.init(source: .swiftData, name: "Item")]
    }

    /// SwiftData APIでItem pageを読みます。
    /// - Parameters:
    ///   - target: `SwiftData/Item` target。
    ///   - offset: 開始offset。
    ///   - limit: 1...500の上限。
    /// - Returns: idとtimestampだけの論理page。
    /// - Throws: target不一致またはSwiftData fetch失敗。
    func readPage(target: DevelopmentDatabaseTarget, offset: Int, limit: Int) async throws -> DevelopmentDatabasePage {
        guard target == .init(source: .swiftData, name: "Item"), offset >= 0, (1...500).contains(limit) else { throw ConnectionSettingsError.unavailable }
        var descriptor = FetchDescriptor<SwiftDataItem>(sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.id)])
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        let items = try context.fetch(descriptor)
        let count = try context.fetchCount(FetchDescriptor<SwiftDataItem>())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = items.enumerated().map { index, item in
            DevelopmentDatabaseRow(id: offset + index, values: [.text(item.id.uuidString.lowercased()), .text(formatter.string(from: item.timestamp))])
        }
        return .init(columns: [.init(name: "id", declaredType: "UUID", primaryKeyOrdinal: 1, isHidden: false), .init(name: "timestamp", declaredType: "Date", primaryKeyOrdinal: 0, isHidden: false)], rows: rows, offset: offset, totalRowCount: count, hasNextPage: offset + rows.count < count, orderingNotice: "SwiftData fetch間の厳密な同一Snapshotは保証されません。")
    }
}
#endif
