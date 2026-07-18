import SwiftData
import SwiftUI

/// Project 24Z の依存関係を組み立て、実行プラットフォーム固有の画面へ渡す起点です。
@main
struct Project24ZApp: App {
    /// アプリ全体で共有するSwiftDataコンテナです。
    private let modelContainer: ModelContainer

    /// Productionの安全な車両登録画面状態を保持します。
    @StateObject private var vehicleRegistrationModel: VehicleRegistrationModel

    /// 永続化コンテナを一度だけ生成します。
    init() {
        _vehicleRegistrationModel = StateObject(wrappedValue: VehicleRegistrationModel())
        do {
            let container = try SwiftDataContainerFactory.makeContainer()
            modelContainer = container
        } catch {
            fatalError("Failed to initialize persistence: \(error)")
        }
    }

    /// 実行Platform固有のRootへComposition済み依存を渡します。
    var body: some Scene {
        WindowGroup {
#if os(macOS)
            MacOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
#elseif os(iOS)
            IOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
#else
            UnsupportedPlatformView()
#endif
        }
        .modelContainer(modelContainer)
    }
}

/// 対応対象外のプラットフォームで明示的な案内を表示します。
private struct UnsupportedPlatformView: View {
    /// 対応対象外であることを示す本文です。
    var body: some View {
        Text("This platform is not supported.")
    }
}
