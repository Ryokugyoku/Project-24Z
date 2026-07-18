#if os(iOS)
import SwiftUI

/// iOS専用の画面階層を開始します。
struct IOSRootView: View {
    @StateObject private var session = AppSessionModel()

    var body: some View {
        if session.isAuthenticated {
            IOSAppShellView(session: session)
        } else {
            IOSLoginView(onSignIn: session.signInWithApple)
        }
    }
}
#endif
