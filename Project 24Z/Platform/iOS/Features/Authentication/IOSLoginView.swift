#if os(iOS)
import SwiftUI

/// iOSでAppleログインの入口だけを表示します。
struct IOSLoginView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack {
            Spacer()

            Button(action: onSignIn) {
                Label("Appleでサインイン", systemImage: "apple.logo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("project24z.login.apple")
            .accessibilityHint("ログイン後のホーム画面を表示します")

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
#endif
