#if DEBUG
import Foundation

/// UIテストとPreview向けfixtureをProduction Compositionから分離して生成します。
@MainActor
enum Project24ZDebugFixtureComposition {
    /// launch environmentで明示されたfixture Modelだけを返します。
    /// - Parameter environment: UIテストが設定するprocess environment。
    /// - Returns: 既知fixtureのModel。指定なしまたは未知名では`nil`。
    static func vehicleRegistrationModel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VehicleRegistrationModel? {
        guard let fixtureName = environment[fixtureEnvironmentKey],
              let fixtureState = VehicleRegistrationPreviewFixtures.state(named: fixtureName) else {
            return nil
        }
        return VehicleRegistrationModel(previewState: fixtureState)
    }

    /// UIテストだけがfixture名を渡すlaunch environment keyです。
    private static let fixtureEnvironmentKey = "PROJECT24Z_VEHICLE_REGISTRATION_FIXTURE"
}
#endif
