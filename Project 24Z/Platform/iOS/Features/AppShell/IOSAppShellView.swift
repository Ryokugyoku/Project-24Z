#if os(iOS)
import SwiftUI

/// iOSでサイドバーと選択中画面を構成します。
struct IOSAppShellView: View {
    /// iOSの主要画面選択を保持するSession Modelです。
    @ObservedObject var session: AppSessionModel

    /// 車両管理画面へ渡すApplication Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// iOS専用のサイドバーとdetailを構成します。
    var body: some View {
        NavigationSplitView {
            List(selection: $session.selectedDestination) {
                NavigationLink(value: AppDestination.home) {
                    Label("ホーム", systemImage: "house")
                }
                .accessibilityIdentifier("project24z.sidebar.home")

                NavigationLink(value: AppDestination.vehicleManagement) {
                    Label("車両管理", systemImage: "car")
                }
                .accessibilityIdentifier("project24z.sidebar.vehicleManagement")

                NavigationLink(value: AppDestination.settings) {
                    Label("設定", systemImage: "gearshape")
                }
                .accessibilityIdentifier("project24z.sidebar.settings")
            }
            .navigationTitle("Project 24Z")
        } detail: {
            IOSSelectedDestinationView(
                session: session,
                destination: session.selectedDestination,
                vehicleRegistrationModel: vehicleRegistrationModel
            )
        }
    }
}

/// iOSのサイドバー選択に対応する画面を表示します。
private struct IOSSelectedDestinationView: View {
    /// Platform Navigation Actionを実行するSession Modelです。
    @ObservedObject var session: AppSessionModel

    /// 現在選択されている主要画面です。
    let destination: AppDestination?

    /// 車両管理画面へ渡すApplication Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// 選択状態に対応するiOS専用画面を表示します。
    var body: some View {
        switch destination {
        case .home:
            IOSHomeView(openConnectionSettings: { session.select(.settings) })
        case .vehicleManagement:
            IOSVehicleManagementView(model: vehicleRegistrationModel)
        case .settings:
            IOSSettingsView()
        case nil:
            ContentUnavailableView("画面を選択してください", systemImage: "sidebar.left")
        }
    }
}
#endif
