import Foundation

/// 永続化方式に依存しない項目エンティティです。
struct Item: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date

    /// 項目を生成します。
    /// - Parameters:
    ///   - id: 項目の一意識別子。
    ///   - timestamp: 項目の作成日時。
    init(id: UUID = UUID(), timestamp: Date) {
        self.id = id
        self.timestamp = timestamp
    }
}
