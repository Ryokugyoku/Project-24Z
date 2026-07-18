#if os(macOS)
import SwiftUI

/// macOSの車両管理画面を表示します。
struct MacOSVehicleManagementView: View {
    var body: some View {
        ContentUnavailableView(
            "車両管理",
            systemImage: "car",
            description: Text("ここに車両の登録と管理機能を追加します。")
        )
        .navigationTitle("車両管理")
        .accessibilityIdentifier("project24z.vehicleManagement")
    }
}
#endif
