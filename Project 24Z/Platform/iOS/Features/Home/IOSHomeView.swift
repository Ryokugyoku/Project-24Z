#if os(iOS)
import SwiftUI

/// iOSのホーム画面を表示します。
struct IOSHomeView: View {
    var body: some View {
        ContentUnavailableView(
            "ホーム",
            systemImage: "house",
            description: Text("ここにホーム画面の内容を追加します。")
        )
        .navigationTitle("ホーム")
        .accessibilityIdentifier("project24z.home")
    }
}
#endif
