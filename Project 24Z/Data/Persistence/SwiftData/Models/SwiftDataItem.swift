import Foundation
import SwiftData

/// SwiftData に保存する項目レコードです。
///
/// この型は Data 層専用です。画面や Domain 層へ直接公開しません。
@Model
final class SwiftDataItem {
    var id: UUID
    var timestamp: Date

    /// 保存用レコードを生成します。
    /// - Parameters:
    ///   - id: Domain エンティティと対応する一意識別子。
    ///   - timestamp: 項目の作成日時。
    init(id: UUID = UUID(), timestamp: Date) {
        self.id = id
        self.timestamp = timestamp
    }
}
