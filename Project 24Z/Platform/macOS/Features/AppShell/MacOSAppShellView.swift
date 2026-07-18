#if os(macOS)
import SwiftUI

/// macOSでサイドバーと選択中画面を構成します。
struct MacOSAppShellView: View {
    @ObservedObject var session: AppSessionModel

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
            MacOSSelectedDestinationView(destination: session.selectedDestination)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

/// macOSのサイドバー選択に対応する画面を表示します。
private struct MacOSSelectedDestinationView: View {
    let destination: AppDestination?

    var body: some View {
        switch destination {
        case .home:
            MacOSHomeView()
        case .vehicleManagement:
            MacOSVehicleManagementView()
        case nil:
            ContentUnavailableView("画面を選択してください", systemImage: "sidebar.left")
        }
    }
}
#endif
