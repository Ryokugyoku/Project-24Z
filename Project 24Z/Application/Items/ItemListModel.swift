import Combine
import Foundation

/// 項目一覧画面の状態とユーザー操作を管理します。
@MainActor
final class ItemListModel: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var errorMessage: String?

    private let repository: any ItemRepository

    /// 一覧画面モデルを生成します。
    /// - Parameter repository: 項目の読み書きを担うリポジトリ。
    init(repository: any ItemRepository) {
        self.repository = repository
    }

    /// 永続化済みの一覧を再読み込みします。
    func load() {
        performAndReload {}
    }

    /// 現在時刻の項目を追加し、一覧を更新します。
    func addItem() {
        performAndReload {
            try repository.insert(Item(timestamp: Date()))
        }
    }

    /// 指定された項目を削除し、一覧を更新します。
    /// - Parameter item: 削除対象のDomainエンティティ。
    func delete(_ item: Item) {
        performAndReload {
            try repository.delete(id: item.id)
        }
    }

    /// 操作後に一覧を再取得し、失敗時は画面表示用のメッセージへ変換します。
    /// - Parameter operation: 再取得前に実行する保存操作。
    private func performAndReload(_ operation: () throws -> Void) {
        do {
            try operation()
            items = try repository.fetchItems()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
