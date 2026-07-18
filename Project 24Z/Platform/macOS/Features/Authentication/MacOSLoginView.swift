#if os(macOS)
import SwiftUI

/// macOSでAppleログインの入口だけを表示します。
struct MacOSLoginView: View {
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            Label("Appleでサインイン", systemImage: "apple.logo")
                .font(.headline)
                .frame(width: 280, height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.black, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("project24z.login.apple")
        .accessibilityHint("ログイン後のホーム画面を表示します")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 520, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
