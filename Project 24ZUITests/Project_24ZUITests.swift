import XCTest

/// ログインから主要画面を選択するまでのユーザーフローを検証します。
final class Project_24ZUITests: XCTestCase {
    /// 各テストを最初の失敗で停止するよう構成します。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 仮のAppleログイン後に車両管理のProduction blocked画面へ到達できることを検証します。
    @MainActor
    func testLoginAndSidebarNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["project24z.login.apple"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["project24z.home"].waitForExistence(timeout: 5))
#if os(iOS)
        app.swipeRight()
#endif

        let vehicleButton = app.buttons["project24z.sidebar.vehicleManagement"]
        XCTAssertTrue(vehicleButton.waitForExistence(timeout: 5))
        vehicleButton.tap()

#if os(macOS)
        let vehicleRegistrationScreen = app.descendants(matching: .any)["project24z.vehicleRegistration.macos"]
#else
        let vehicleRegistrationScreen = app.descendants(matching: .any)["project24z.vehicleRegistration.ios"]
#endif
        XCTAssertTrue(vehicleRegistrationScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["project24z.vehicleRegistration.status"].exists)
        let unavailableReason = app.descendants(matching: .any)["project24z.vehicleRegistration.unavailableReason"]
        scrollToElement(unavailableReason, in: app)
        XCTAssertTrue(unavailableReason.exists)

        let primaryAction = app.buttons["project24z.vehicleRegistration.primaryAction"]
        scrollToElement(primaryAction, in: app)
        XCTAssertTrue(primaryAction.exists)
        XCTAssertFalse(primaryAction.isEnabled)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "vehicle-registration-blocked"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// DEBUG限定fixtureを実アプリのiOS／macOS別Viewツリーで表示し、主要状態を画像化します。
    @MainActor
    func testMajorVehicleRegistrationFixturesRender() throws {
        let scenarios = [
            ("blocked", "project24z.vehicleRegistration.unavailableReason"),
            ("no-identifier", "project24z.vehicleRegistration.unavailableReason"),
            ("duplicate-active", "project24z.vehicleRegistration.maskedIdentifier"),
            ("duplicate-archived", "project24z.vehicleRegistration.archivedCandidate"),
            ("restore-required", "project24z.vehicleRegistration.restoreRequired"),
            ("restoring-archived", "project24z.vehicleRegistration.restoringArchivedVehicle"),
            ("restore-failed", "project24z.vehicleRegistration.restoreRequired"),
            ("conflict", "project24z.vehicleRegistration.conflict"),
            ("registration-ready", "project24z.vehicleRegistration.displayName"),
            ("binding-pending", "project24z.vehicleRegistration.bindingPending")
        ]

        for (fixtureName, expectedIdentifier) in scenarios {
            let app = XCUIApplication()
            app.launchEnvironment["PROJECT24Z_VEHICLE_REGISTRATION_FIXTURE"] = fixtureName
            app.launch()

            let loginButton = app.buttons["project24z.login.apple"]
            XCTAssertTrue(loginButton.waitForExistence(timeout: 5), fixtureName)
            loginButton.tap()

            XCTAssertTrue(app.descendants(matching: .any)["project24z.home"].waitForExistence(timeout: 5), fixtureName)
#if os(iOS)
            app.swipeRight()
#endif
            let vehicleButton = app.buttons["project24z.sidebar.vehicleManagement"]
            XCTAssertTrue(vehicleButton.waitForExistence(timeout: 5), fixtureName)
            vehicleButton.tap()

#if os(macOS)
            let vehicleRegistrationScreen = app.descendants(matching: .any)["project24z.vehicleRegistration.macos"]
#else
            let vehicleRegistrationScreen = app.descendants(matching: .any)["project24z.vehicleRegistration.ios"]
#endif
            XCTAssertTrue(vehicleRegistrationScreen.waitForExistence(timeout: 5), fixtureName)
            let expectedElement = app.descendants(matching: .any)[expectedIdentifier]
            scrollToElement(expectedElement, in: app)
            XCTAssertTrue(expectedElement.waitForExistence(timeout: 5), fixtureName)

            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "vehicle-registration-\(fixtureName)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    /// iOS Formの下部cellをaccessibility hierarchyへ確実に読み込ませます。
    /// - Parameters:
    ///   - element: 検査対象要素。
    ///   - app: swipe対象のアプリケーション。
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
#if os(iOS)
        for _ in 0..<8 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
#endif
    }
}
