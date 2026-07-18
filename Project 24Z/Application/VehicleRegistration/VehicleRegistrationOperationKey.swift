/// 同じpresentation内で再dispatchしてはならないprocess内操作を識別します。
enum VehicleRegistrationOperationKey: Equatable, Hashable, Sendable {
    /// Transport候補への接続開始操作です。
    case startConnection(
        VehicleRegistrationTransportSelection,
        VehicleRegistrationPresentationRevision
    )

    /// 現在処理の取消操作です。
    case cancelConnection(VehicleRegistrationPresentationRevision)

    /// Adapter候補の選択操作です。
    case selectAdapter(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// 識別再試行操作です。
    case retryIdentification(VehicleRegistrationPresentationRevision)

    /// 既存車両候補の選択操作です。
    case selectExistingVehicleCandidate(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// 新規登録確認操作です。
    case confirmRegistration(VehicleRegistrationPresentationRevision)

    /// archived車両の復元確認操作です。
    case confirmArchivedVehicleRestore(
        VehicleRegistrationPresentationIdentifier,
        Int,
        VehicleRegistrationPresentationRevision
    )

    /// Conflictレビュー操作です。
    case reviewConflict(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// Session binding再試行操作です。
    case retrySessionBinding(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// 未割当Session継続操作です。
    case continueSessionUnassigned(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// Session終了操作です。
    case endSession(
        VehicleRegistrationPresentationIdentifier,
        VehicleRegistrationPresentationRevision
    )

    /// 型付きActionからprocess内操作キーを生成します。
    /// - Parameter action: Platformから通知されたAction。
    init(action: VehicleRegistrationAction) {
        switch action {
        case .startConnection(let selection, let revision):
            self = .startConnection(selection, revision)
        case .cancelConnection(let revision):
            self = .cancelConnection(revision)
        case .selectAdapter(let identifier, let revision):
            self = .selectAdapter(identifier, revision)
        case .retryIdentification(let revision):
            self = .retryIdentification(revision)
        case .selectExistingVehicleCandidate(let identifier, let revision):
            self = .selectExistingVehicleCandidate(identifier, revision)
        case .confirmRegistration(_, let revision):
            self = .confirmRegistration(revision)
        case .confirmArchivedVehicleRestore(let identifier, let lifecycleRevision, let revision):
            self = .confirmArchivedVehicleRestore(identifier, lifecycleRevision, revision)
        case .reviewConflict(let identifier, let revision):
            self = .reviewConflict(identifier, revision)
        case .retrySessionBinding(let identifier, let revision):
            self = .retrySessionBinding(identifier, revision)
        case .continueSessionUnassigned(let identifier, let revision):
            self = .continueSessionUnassigned(identifier, revision)
        case .endSession(let identifier, let revision):
            self = .endSession(identifier, revision)
        }
    }
}
