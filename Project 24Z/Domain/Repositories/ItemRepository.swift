import Foundation

/// 項目の保存先を抽象化する境界です。
@MainActor
protocol ItemRepository {
    /// 保存済み項目を日時の降順で返します。
    /// - Returns: 永続化方式に依存しない項目一覧。
    /// - Throws: 保存先からの読み出しに失敗した場合のエラー。
    func fetchItems() throws -> [Item]

    /// 項目を永続化します。
    /// - Parameter item: 保存するDomainエンティティ。
    /// - Throws: 保存処理に失敗した場合のエラー。
    func insert(_ item: Item) throws

    /// 指定された項目を削除します。
    /// - Parameter id: 削除する項目の一意識別子。
    /// - Throws: 検索または削除に失敗した場合のエラー。
    func delete(id: UUID) throws
}
