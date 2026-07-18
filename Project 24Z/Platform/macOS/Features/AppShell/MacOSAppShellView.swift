#if os(macOS)
import SwiftUI

/// macOSでサイドバーと選択中画面を構成します。
struct MacOSAppShellView: View {
    /// macOSの主要画面選択を保持するSession Modelです。
    @ObservedObject var session: AppSessionModel

    /// 車両管理画面へ渡すApplication Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// macOS専用のサイドバーとdetailを構成します。
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
            }
            .navigationTitle("Project 24Z")
            .frame(minWidth: 210)
        } detail: {
            MacOSSelectedDestinationView(
                destination: session.selectedDestination,
                vehicleRegistrationModel: vehicleRegistrationModel
            )
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

/// macOSのサイドバー選択に対応する画面を表示します。
private struct MacOSSelectedDestinationView: View {
    /// 現在選択されている主要画面です。
    let destination: AppDestination?

    /// 車両管理画面へ渡すApplication Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// 選択状態に対応するmacOS専用画面を表示します。
    var body: some View {
        switch destination {
        case .home:
            MacOSHomeView()
        case .vehicleManagement:
            MacOSVehicleManagementView(model: vehicleRegistrationModel)
        case nil:
            ContentUnavailableView("画面を選択してください", systemImage: "sidebar.left")
        }
    }
}
#endif
