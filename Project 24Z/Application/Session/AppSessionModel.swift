import Combine

/// ログイン状態とログイン後に選択中の画面を管理します。
@MainActor
final class AppSessionModel: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published var selectedDestination: AppDestination? = .home

    /// 未ログインかつホーム選択済みの初期状態を生成します。
    init() {}

    /// 仮のAppleログインを完了状態にし、ホーム画面を選択します。
    ///
    /// 実際のApple ID認証は行わず、ログイン後画面を確認するための状態遷移だけを行います。
    func signInWithApple() {
        selectedDestination = .home
        isAuthenticated = true
    }

    /// サイドバーから表示する画面を選択します。
    /// - Parameter destination: 表示対象の画面。
    func select(_ destination: AppDestination) {
        selectedDestination = destination
    }
}
