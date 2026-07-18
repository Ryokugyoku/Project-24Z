#if os(macOS)
import SwiftUI

/// macOSのホーム画面を表示します。
struct MacOSHomeView: View {
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
