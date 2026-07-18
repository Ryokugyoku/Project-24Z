import Combine
import Foundation

/// 車両登録画面の表示状態と操作拒否境界を管理します。
@MainActor
final class VehicleRegistrationModel: ObservableObject {
    /// Platformへ公開する現在状態です。
    @Published private(set) var state: VehicleRegistrationPresentationState

    /// dispatch開始から完了まで占有しているprocess内操作です。
    private var inFlightOperations: Set<VehicleRegistrationOperationKey> = []

    /// 同じpresentationで処理済みとなったprocess内操作です。
    private var processedOperations: Set<VehicleRegistrationOperationKey> = []

    /// Production依存が未実装である安全なblocked状態を生成します。
    init() {
#if DEBUG
        if let fixtureName = ProcessInfo.processInfo.environment[Self.fixtureEnvironmentKey],
           let fixtureState = VehicleRegistrationPreviewFixtures.state(named: fixtureName) {
            state = fixtureState
            return
        }
#endif
        state = .blocked(Self.productionUnavailableDisplay)
    }

#if DEBUG
    /// Previewと単体テストだけで任意の表示状態を生成します。
    /// - Parameter previewState: 表示検証に使用するfixture状態。
    init(previewState: VehicleRegistrationPresentationState) {
        state = previewState
    }
#endif

#if DEBUG
    /// UIテストだけがfixture名を渡すlaunch environment keyです。
    private static let fixtureEnvironmentKey = "PROJECT24Z_VEHICLE_REGISTRATION_FIXTURE"
#endif

    /// Actionのrevisionと重複を検証し、未実装処理を成功させず拒否します。
    /// - Parameter action: Platformから通知された型付きAction。
    /// - Returns: stale、重複、未実装のいずれかの拒否結果。
    @discardableResult
    func perform(_ action: VehicleRegistrationAction) -> VehicleRegistrationActionDisposition {
        guard action.presentationRevision == state.revision else {
            return .rejectedStalePresentation
        }
        guard state.allows(action) else {
            return .rejectedInvalidState
        }
        guard hasCurrentLifecycleRevision(for: action) else {
            return .rejectedStaleLifecycleRevision
        }

        let operation = VehicleRegistrationOperationKey(action: action)
        guard !inFlightOperations.contains(operation),
              !processedOperations.contains(operation) else {
            return .rejectedDuplicateAction
        }

        inFlightOperations.insert(operation)
        inFlightOperations.remove(operation)
        processedOperations.insert(operation)
        return .rejectedUnavailable
    }

    /// archived復元Actionのlifecycle revisionが現在候補と一致するかを返します。
    /// - Parameter action: 検証する型付きAction。
    /// - Returns: lifecycle revision検証が不要、または現在値と一致する場合は`true`。
    private func hasCurrentLifecycleRevision(for action: VehicleRegistrationAction) -> Bool {
        guard case .confirmArchivedVehicleRestore(_, let lifecycleRevision, _) = action else {
            return true
        }
        guard case .archivedRestoreRequired(let candidate) = state else {
            return false
        }
        return lifecycleRevision == candidate.lifecycleRevision
    }

    /// Productionで表示する安定した利用不能状態です。
    private static var productionUnavailableDisplay: VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "車両登録は利用できません",
            message: "安全な接続・識別・登録処理はまだ実装されていません。",
            sessionSummary: "Sessionは車両未割当のまま保持されます。",
            unavailableReason: "通信と車両登録のProduction実装が未提供です。",
            actionDisabledReason: "接続、識別、登録、復元、Session所属は現在実行できません。",
            revision: VehicleRegistrationPresentationRevision(1)
        )
    }
}
