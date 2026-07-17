import SwiftData

/// SwiftData のスキーマと保存設定を一か所で管理します。
enum SwiftDataContainerFactory {
    /// アプリ用の永続化コンテナを生成します。
    /// - Parameter inMemory: `true` の場合はテスト・Preview用のメモリ内保存を使用します。
    /// - Returns: 現在のSwiftDataスキーマで構成したコンテナ。
    /// - Throws: スキーマまたは保存先の初期化に失敗した場合のエラー。
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([SwiftDataItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
