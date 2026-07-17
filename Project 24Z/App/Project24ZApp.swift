import SwiftData
import SwiftUI

/// Project 24Z の依存関係を組み立て、実行プラットフォーム固有の画面へ渡す起点です。
@main
struct Project24ZApp: App {
    private let modelContainer: ModelContainer
    private let itemRepository: any ItemRepository

    /// 永続化コンテナとリポジトリを一度だけ生成します。
    init() {
        do {
            let container = try SwiftDataContainerFactory.makeContainer()
            modelContainer = container
            itemRepository = SwiftDataItemRepository(modelContext: container.mainContext)
        } catch {
            fatalError("Failed to initialize persistence: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            MacOSRootView(itemRepository: itemRepository)
#elseif os(iOS)
            IOSRootView(itemRepository: itemRepository)
#else
            UnsupportedPlatformView()
#endif
        }
        .modelContainer(modelContainer)
    }
}

/// 対応対象外のプラットフォームで明示的な案内を表示します。
private struct UnsupportedPlatformView: View {
    var body: some View {
        Text("This platform is not supported.")
    }
}
