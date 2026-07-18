#if os(macOS)
import SwiftUI

/// macOS専用の画面階層を開始します。
struct MacOSRootView: View {
    /// macOSのログイン状態と主要画面選択を保持します。
    @StateObject private var session = AppSessionModel()

    /// AppのComposition Rootから受け取る車両登録画面Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// ログイン状態に応じてmacOS専用画面階層を表示します。
    var body: some View {
        if session.isAuthenticated {
            MacOSAppShellView(
                session: session,
                vehicleRegistrationModel: vehicleRegistrationModel
            )
        } else {
            MacOSLoginView(onSignIn: session.signInWithApple)
        }
    }
}
#endif
