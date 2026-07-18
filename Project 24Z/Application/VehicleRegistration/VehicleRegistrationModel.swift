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

    /// Production Composition済みApplicationサービスを生存期間中保持します。
    private let productionServices: VehicleRegistrationProductionServices?

    /// Compositionを経由しない呼出しを安全なblocked状態で生成します。
    init() {
        productionServices = nil
        state = .blocked(Self.productionUnavailableDisplay)
    }

    /// Production Composition済みサービスを保持し、Hard Gate未達状態を公開します。
    /// - Parameter productionServices: Data／Runtimeへ接続済みのApplicationサービス。
    init(productionServices: VehicleRegistrationProductionServices) {
        self.productionServices = productionServices
        state = .blocked(Self.productionUnavailableDisplay(reason: productionServices.blockedReason))
    }

#if DEBUG
    /// Previewと単体テストだけで任意の表示状態を生成します。
    /// - Parameter previewState: 表示検証に使用するfixture状態。
    init(previewState: VehicleRegistrationPresentationState) {
        productionServices = nil
        state = previewState
    }
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
        productionUnavailableDisplay(
            reason: "Production Compositionが提供されていません。"
        )
    }

    /// Production Hard Gate理由を持つ安全な利用不能表示を生成します。
    /// - Parameter reason: 機密情報を含まない安定した停止理由。
    /// - Returns: 登録成功を表さないblocked表示値。
    private static func productionUnavailableDisplay(
        reason: String
    ) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "車両登録は利用できません",
            message: "安全条件を満たすまでProductionの接続・識別・登録を開始しません。",
            sessionSummary: "Sessionは車両未割当のまま保持されます。",
            unavailableReason: reason,
            actionDisabledReason: "接続、識別、登録、復元、Session所属は現在実行できません。",
            revision: VehicleRegistrationPresentationRevision(1)
        )
    }
}
