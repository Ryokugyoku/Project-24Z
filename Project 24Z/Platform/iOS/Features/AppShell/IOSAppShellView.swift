#if os(iOS)
import SwiftUI

/// iOSでサイドバーと選択中画面を構成します。
struct IOSAppShellView: View {
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
        } detail: {
            IOSSelectedDestinationView(destination: session.selectedDestination)
        }
    }
}

/// iOSのサイドバー選択に対応する画面を表示します。
private struct IOSSelectedDestinationView: View {
    let destination: AppDestination?

    var body: some View {
        switch destination {
        case .home:
            IOSHomeView()
        case .vehicleManagement:
            IOSVehicleManagementView()
        case nil:
            ContentUnavailableView("画面を選択してください", systemImage: "sidebar.left")
        }
    }
}
#endif
