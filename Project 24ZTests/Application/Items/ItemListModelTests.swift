import Foundation
import Testing
@testable import Project_24Z

/// `ItemListModel` の保存操作と表示状態の同期を検証します。
@MainActor
struct ItemListModelTests {
    /// 追加操作がRepositoryへ保存され、一覧にも反映されることを検証します。
    @Test
    func addItemPersistsAndReloadsItems() {
        let repository = FakeItemRepository()
        let model = ItemListModel(repository: repository)

        model.addItem()

        #expect(repository.items.count == 1)
        #expect(model.items == repository.items)
        #expect(model.errorMessage == nil)
    }

    /// 削除操作がRepositoryと一覧の双方へ反映されることを検証します。
    @Test
    func deleteRemovesItemAndReloadsItems() {
        let item = Item(timestamp: Date(timeIntervalSince1970: 1_000))
        let repository = FakeItemRepository(items: [item])
        let model = ItemListModel(repository: repository)
        model.load()

        model.delete(item)

        #expect(repository.items.isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.errorMessage == nil)
    }
}

/// Applicationテストだけで使用するメモリ内Repositoryです。
@MainActor
private final class FakeItemRepository: ItemRepository {
    private(set) var items: [Item]

    /// 初期状態を指定してFakeを生成します。
    /// - Parameter items: 取得対象として保持する項目一覧。
    init(items: [Item] = []) {
        self.items = items
    }

    /// 保持中の項目を返します。
    /// - Returns: 日時の降順に並べた項目一覧。
    func fetchItems() throws -> [Item] {
        items.sorted { $0.timestamp > $1.timestamp }
    }

    /// 項目をメモリ内配列へ追加します。
    /// - Parameter item: 追加対象の項目。
    func insert(_ item: Item) throws {
        items.append(item)
    }

    /// 指定IDの項目をメモリ内配列から削除します。
    /// - Parameter id: 削除対象の一意識別子。
    func delete(id: UUID) throws {
        items.removeAll { $0.id == id }
    }
}
