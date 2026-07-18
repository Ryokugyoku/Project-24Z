/// 車両登録フローをPlatformへ公開するレイアウト非依存状態です。
enum VehicleRegistrationPresentationState: Equatable, Sendable {
    /// 接続を開始していない状態です。
    case disconnected(VehicleRegistrationDisconnectedPresentation)

    /// 接続処理中です。
    case connecting(VehicleRegistrationDisplayValues)

    /// Adapter capabilityを確認中です。
    case adapterChecking(VehicleRegistrationDisplayValues)

    /// 車両識別中です。
    case identifying(VehicleRegistrationDisplayValues)

    /// 有効な識別子を得られなかった状態です。
    case identificationUnavailable(VehicleRegistrationDisplayValues)

    /// activeまたはarchivedの既存車両候補です。
    case duplicateCandidate(VehicleRegistrationDuplicateCandidate)

    /// archived車両へScanを保持し、明示復元を待つ状態です。
    case archivedRestoreRequired(VehicleRegistrationDuplicateCandidate)

    /// archived車両を明示的に復元している状態です。
    case restoringArchivedVehicle(VehicleRegistrationDisplayValues)

    /// 候補の競合を安全にレビューする状態です。
    case conflict(VehicleRegistrationDisplayValues)

    /// 新規登録確認が可能な状態です。
    case registrationReady(VehicleRegistrationDisplayValues)

    /// 登録処理中です。
    case registering(VehicleRegistrationDisplayValues)

    /// 登録済み状態です。Session所属待ちも関連値で区別します。
    case registered(VehicleRegistrationRegisteredPresentation)

    /// 回復条件を満たすまで処理を開始できない状態です。
    case blocked(VehicleRegistrationDisplayValues)

    /// 現在attemptでは自動継続しない終端失敗です。
    case failed(VehicleRegistrationDisplayValues)

    /// 現在状態の安全な表示値を返します。
    var display: VehicleRegistrationDisplayValues {
        switch self {
        case .connecting(let display),
             .adapterChecking(let display),
             .identifying(let display),
             .identificationUnavailable(let display),
             .conflict(let display),
             .registrationReady(let display),
             .registering(let display),
             .blocked(let display),
             .failed(let display):
            display
        case .disconnected(let disconnected):
            disconnected.display
        case .duplicateCandidate(let candidate):
            candidate.display
        case .archivedRestoreRequired(let candidate):
            candidate.display
        case .restoringArchivedVehicle(let display):
            display
        case .registered(let registered):
            registered.display
        }
    }

    /// 現在表示している状態の世代です。
    var revision: VehicleRegistrationPresentationRevision {
        display.revision
    }

    /// 車両登録が確定済みかを返します。
    var isRegistered: Bool {
        if case .registered = self {
            return true
        }
        return false
    }

    /// 現在状態がSession binding再試行を許可するかを返します。
    var allowsSessionBindingRetry: Bool {
        guard case .registered(let registered) = self else {
            return false
        }
        return registered.sessionBindingState == .pending
    }

    /// 現在Stateが指定ActionをPlatformへ公開できるかを返します。
    /// - Parameter action: 公開可否を検証するAction。
    /// - Returns: 状態機械上で現在Stateから通知可能な場合は`true`。
    func allows(_ action: VehicleRegistrationAction) -> Bool {
        switch (self, action) {
        case (.disconnected, .startConnection),
             (.disconnected, .selectAdapter),
             (.identificationUnavailable, .retryIdentification),
             (.identificationUnavailable, .continueSessionUnassigned),
             (.identificationUnavailable, .endSession),
             (.duplicateCandidate, .selectExistingVehicleCandidate),
             (.archivedRestoreRequired, .confirmArchivedVehicleRestore),
             (.archivedRestoreRequired, .continueSessionUnassigned),
             (.archivedRestoreRequired, .endSession),
             (.conflict, .reviewConflict),
             (.conflict, .continueSessionUnassigned),
             (.conflict, .endSession),
             (.registrationReady, .confirmRegistration),
             (.registered, .endSession),
             (.failed, .retryIdentification),
             (.failed, .continueSessionUnassigned),
             (.failed, .endSession):
            true
        case (_, .cancelConnection):
            display.isCancellationAvailable
        case (.registered(let registered), .retrySessionBinding):
            registered.sessionBindingState == .pending
        default:
            false
        }
    }
}
