import Testing
@testable import Project_24Z

/// `AppSessionModel` のログインと画面選択の状態遷移を検証します。
@MainActor
struct AppSessionModelTests {
    /// 初期状態が未ログインかつホーム選択済みであることを検証します。
    @Test
    func initialStateShowsLoginBeforeHome() {
        let model = AppSessionModel()

        #expect(model.isAuthenticated == false)
        #expect(model.selectedDestination == .home)
    }

    /// 仮ログイン操作がホーム画面へ遷移することを検証します。
    @Test
    func signInSelectsHomeAndAuthenticates() {
        let model = AppSessionModel()
        model.select(.vehicleManagement)

        model.signInWithApple()

        #expect(model.isAuthenticated)
        #expect(model.selectedDestination == .home)
    }

    /// サイドバー操作が指定された画面へ選択を切り替えることを検証します。
    @Test
    func selectChangesDestination() {
        let model = AppSessionModel()

        model.select(.vehicleManagement)

        #expect(model.selectedDestination == .vehicleManagement)
    }
}
