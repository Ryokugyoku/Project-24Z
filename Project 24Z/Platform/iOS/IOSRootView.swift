#if os(iOS)
import SwiftUI

/// iOS専用の画面階層を開始します。
struct IOSRootView: View {
    /// iOSのログイン状態と主要画面選択を保持します。
    @StateObject private var session = AppSessionModel()

    /// AppのComposition Rootから受け取る車両登録画面Modelです。
    @ObservedObject var vehicleRegistrationModel: VehicleRegistrationModel

    /// ログイン状態に応じてiOS専用画面階層を表示します。
    var body: some View {
        if session.isAuthenticated {
            IOSAppShellView(
                session: session,
                vehicleRegistrationModel: vehicleRegistrationModel
            )
        } else {
            IOSLoginView(onSignIn: session.signInWithApple)
        }
    }
}
#endif
