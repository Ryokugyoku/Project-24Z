#if os(macOS)
import SwiftUI

/// macOS専用の画面階層を開始します。
struct MacOSRootView: View {
    @StateObject private var session = AppSessionModel()

    var body: some View {
        if session.isAuthenticated {
            MacOSAppShellView(session: session)
        } else {
            MacOSLoginView(onSignIn: session.signInWithApple)
        }
    }
}
#endif
