#if os(iOS)
import SwiftUI

/// iOSの車両管理画面を表示します。
struct IOSVehicleManagementView: View {
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
