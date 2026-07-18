import XCTest

/// ログインから主要画面を選択するまでのユーザーフローを検証します。
final class Project_24ZUITests: XCTestCase {
    /// 各テストを最初の失敗で停止するよう構成します。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 仮のAppleログイン後にホームと車両管理を表示できることを検証します。
    @MainActor
    func testLoginAndSidebarNavigation() throws {
#if os(macOS)
        throw XCTSkip("iOSの折りたたみサイドバー操作を対象とするUIテストです。")
#else
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["project24z.login.apple"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["project24z.home"].waitForExistence(timeout: 5))
        app.swipeRight()

        let vehicleButton = app.buttons["project24z.sidebar.vehicleManagement"]
        XCTAssertTrue(vehicleButton.waitForExistence(timeout: 5))
        vehicleButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["project24z.vehicleManagement"].waitForExistence(timeout: 5))
#endif
    }
}
