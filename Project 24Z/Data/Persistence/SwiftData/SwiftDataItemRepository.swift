import Foundation
import SwiftData

/// SwiftData を使用する項目リポジトリです。
@MainActor
final class SwiftDataItemRepository: ItemRepository {
    private let modelContext: ModelContext

    /// SwiftData のコンテキストを受け取ります。
    /// - Parameter modelContext: このリポジトリが所有して操作するコンテキスト。
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// SwiftDataレコードを日時の降順で取得しDomainエンティティへ変換します。
    /// - Returns: 永続化方式を公開しない項目一覧。
    /// - Throws: SwiftDataの取得に失敗した場合のエラー。
    func fetchItems() throws -> [Item] {
        let descriptor = FetchDescriptor<SwiftDataItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(Self.makeDomainItem)
    }

    /// DomainエンティティをSwiftDataレコードへ変換して保存します。
    /// - Parameter item: 保存するDomainエンティティ。
    /// - Throws: SwiftDataの保存に失敗した場合のエラー。
    func insert(_ item: Item) throws {
        modelContext.insert(SwiftDataItem(id: item.id, timestamp: item.timestamp))
        try modelContext.save()
    }

    /// 一意識別子に一致するSwiftDataレコードを削除します。
    /// - Parameter id: 削除する項目の一意識別子。
    /// - Throws: SwiftDataの検索または保存に失敗した場合のエラー。
    func delete(id: UUID) throws {
        var descriptor = FetchDescriptor<SwiftDataItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    /// SwiftDataレコードをDomainエンティティへ変換します。
    /// - Parameter record: 変換元の保存レコード。
    /// - Returns: 永続化方式に依存しない項目。
    private static func makeDomainItem(from record: SwiftDataItem) -> Item {
        Item(id: record.id, timestamp: record.timestamp)
    }
}
