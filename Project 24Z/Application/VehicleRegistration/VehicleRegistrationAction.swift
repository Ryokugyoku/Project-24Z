/// 車両登録画面からApplicationへ通知できる操作です。
enum VehicleRegistrationAction: Equatable, Hashable, Sendable {
    /// 選択済みの不透明なTransport候補で車両接続を開始します。
    case startConnection(
        transportSelection: VehicleRegistrationTransportSelection,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 現在の接続処理を取り消します。
    case cancelConnection(revision: VehicleRegistrationPresentationRevision)

    /// discovery snapshot内のAdapter候補を選択します。
    case selectAdapter(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 新しい識別attemptを開始します。
    case retryIdentification(revision: VehicleRegistrationPresentationRevision)

    /// 一意に照合された既存車両候補を選択します。
    case selectExistingVehicleCandidate(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// mask済み識別結果に基づく登録を確認します。
    case confirmRegistration(
        displayName: String?,
        revision: VehicleRegistrationPresentationRevision
    )

    /// Scan追加済みarchived車両の明示復元を確認します。
    case confirmArchivedVehicleRestore(
        identifier: VehicleRegistrationPresentationIdentifier,
        lifecycleRevision: Int,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 競合の安全な説明をレビューします。
    case reviewConflict(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 登録済み車両へのSession所属を再試行します。
    case retrySessionBinding(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 現在Sessionを車両未割当のまま継続します。
    case continueSessionUnassigned(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// 既存Storage停止順序に従って現在Sessionを終了します。
    case endSession(
        identifier: VehicleRegistrationPresentationIdentifier,
        revision: VehicleRegistrationPresentationRevision
    )

    /// Action生成時に表示されていたrevisionを返します。
    var presentationRevision: VehicleRegistrationPresentationRevision {
        switch self {
        case .cancelConnection(let revision),
             .retryIdentification(let revision):
            revision
        case .startConnection(_, let revision),
             .selectAdapter(_, let revision),
             .selectExistingVehicleCandidate(_, let revision),
             .confirmRegistration(_, let revision),
             .confirmArchivedVehicleRestore(_, _, let revision),
             .reviewConflict(_, let revision),
             .retrySessionBinding(_, let revision),
             .continueSessionUnassigned(_, let revision),
             .endSession(_, let revision):
            revision
        }
    }
}
