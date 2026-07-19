import SwiftData
import SwiftUI

/// Project 24Z の依存関係を組み立て、実行プラットフォーム固有の画面へ渡す起点です。
@main
struct Project24ZApp: App {
    /// Productionの依存関係と生存期間を所有します。
    private let productionComposition: Project24ZProductionComposition

    /// Productionの安全な車両登録画面状態を保持します。
    @StateObject private var vehicleRegistrationModel: VehicleRegistrationModel

    /// 永続化コンテナを一度だけ生成します。
    init() {
        do {
            let composition = try Project24ZProductionComposition()
            productionComposition = composition
#if DEBUG
            let model = Project24ZDebugFixtureComposition.vehicleRegistrationModel()
                ?? composition.vehicleRegistrationModel
#else
            let model = composition.vehicleRegistrationModel
#endif
            _vehicleRegistrationModel = StateObject(wrappedValue: model)
        } catch {
            fatalError("Failed to initialize persistence: \(error)")
        }
    }

    /// 実行Platform固有のRootへComposition済み依存を渡します。
    var body: some Scene {
#if os(macOS)
        WindowGroup {
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
            MacOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
                .environmentObject(productionComposition.connectionSettingsModel)
                .environmentObject(productionComposition.dashboardModel)
                .environmentObject(productionComposition.developmentDatabaseBrowserModel)
#else
            MacOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
                .environmentObject(productionComposition.connectionSettingsModel)
                .environmentObject(productionComposition.dashboardModel)
#endif
        }
        .defaultSize(width: 900, height: 640)
        .modelContainer(productionComposition.modelContainer)
#elseif os(iOS)
        WindowGroup {
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
            IOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
                .environmentObject(productionComposition.connectionSettingsModel)
                .environmentObject(productionComposition.dashboardModel)
                .environmentObject(productionComposition.developmentDatabaseBrowserModel)
#else
            IOSRootView(vehicleRegistrationModel: vehicleRegistrationModel)
                .environmentObject(productionComposition.connectionSettingsModel)
                .environmentObject(productionComposition.dashboardModel)
#endif
        }
        .modelContainer(productionComposition.modelContainer)
#else
        WindowGroup {
            UnsupportedPlatformView()
        }
        .modelContainer(productionComposition.modelContainer)
#endif
    }
}

/// 対応対象外のプラットフォームで明示的な案内を表示します。
private struct UnsupportedPlatformView: View {
    /// 対応対象外であることを示す本文です。
    var body: some View {
        Text("This platform is not supported.")
    }
}
