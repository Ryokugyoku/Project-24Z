#if DEBUG
/// Previewと単体テストだけで使用する架空の車両登録状態です。
enum VehicleRegistrationPreviewFixtures {
    /// Transport／Adapter候補を安全な表示名で選択する接続前状態です。
    static let disconnected = VehicleRegistrationPresentationState.disconnected(
        VehicleRegistrationDisconnectedPresentation(
            display: display(
                title: "接続方法を選択",
                message: "利用可能な架空TransportとAdapter候補を選択してください。"
            ),
            transportOptions: [
                VehicleRegistrationTransportOption(
                    transportSelection: VehicleRegistrationTransportSelection("fixture-transport-a"),
                    adapterSelection: VehicleRegistrationPresentationIdentifier("fixture-adapter-a"),
                    displayName: "Preview Wired Adapter",
                    isSelected: true
                ),
                VehicleRegistrationTransportOption(
                    transportSelection: VehicleRegistrationTransportSelection("fixture-transport-b"),
                    adapterSelection: VehicleRegistrationPresentationIdentifier("fixture-adapter-b"),
                    displayName: "Preview Local Adapter",
                    isSelected: false
                )
            ]
        )
    )

    /// 接続処理中で取消可能な状態です。
    static let connecting = VehicleRegistrationPresentationState.connecting(
        display(
            title: "接続しています",
            message: "選択済みの架空Adapterへ接続しています。",
            adapterDisplayName: "Preview Wired Adapter",
            progress: 0.25,
            isCancellationAvailable: true
        )
    )

    /// 選択済みAdapterのcapabilityを確認中で取消可能な状態です。
    static let adapterChecking = VehicleRegistrationPresentationState.adapterChecking(
        display(
            title: "Adapter capabilityを確認しています",
            message: "選択済みAdapterの利用可能機能を安全に確認しています。",
            adapterDisplayName: "Preview Wired Adapter",
            progress: 0.45,
            isCancellationAvailable: true
        )
    )

    /// 車両識別中で取消可能な状態です。
    static let identifying = VehicleRegistrationPresentationState.identifying(
        display(
            title: "車両を識別しています",
            message: "2個の架空ECU応答を確認しています。",
            progress: 0.65,
            isCancellationAvailable: true
        )
    )

    /// 登録可能な識別子がない状態です。
    static let identificationUnavailable = VehicleRegistrationPresentationState.identificationUnavailable(
        display(
            title: "車両を識別できません",
            message: "登録に使用できる識別子がありません。",
            unavailableReason: "有効なmask済み識別結果を取得できませんでした。",
            actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-no-identifier-session")
        )
    )

    /// active車両の重複候補です。
    static let duplicateActive = VehicleRegistrationPresentationState.duplicateCandidate(
        candidate(
            lifecycle: .active,
            lifecycleRevision: 3,
            title: "登録済み車両が見つかりました",
            message: "現在利用中の車両候補を確認してください。",
            maskedIdentifier: "•••• ACTIVE-24Z",
            vehicleDisplayName: "Preview Active Vehicle",
            identifier: "fixture-active-candidate"
        )
    )

    /// archived車両の重複候補です。
    static let duplicateArchived = VehicleRegistrationPresentationState.duplicateCandidate(
        candidate(
            lifecycle: .archived,
            lifecycleRevision: 7,
            title: "アーカイブ済み車両が見つかりました",
            message: "Scan保持後も明示復元するまで登録済みにはなりません。",
            maskedIdentifier: "•••• ARCHIVE-24Z",
            vehicleDisplayName: "Preview Archived Vehicle",
            identifier: "fixture-archived-candidate"
        )
    )

    /// valid Scan保持後にarchived車両の明示復元を待つ状態です。
    static let archivedRestoreRequired = VehicleRegistrationPresentationState.archivedRestoreRequired(
        candidate(
            lifecycle: .archived,
            lifecycleRevision: 8,
            title: "車両の復元が必要です",
            message: "架空Scanは保持済みですが、車両はまだアーカイブ済みです。",
            maskedIdentifier: "•••• RESTORE-24Z",
            vehicleDisplayName: "Preview Restore Vehicle",
            identifier: "fixture-restore-candidate"
        )
    )

    /// archived車両を明示復元中で取消可能な状態です。
    static let restoringArchivedVehicle = VehicleRegistrationPresentationState.restoringArchivedVehicle(
        display(
            title: "アーカイブ車両を復元しています",
            message: "登録処理とは別の復元処理を実行しています。",
            vehicleDisplayName: "Preview Restore Vehicle",
            progress: 0.55,
            sessionSummary: "Sessionは未割当のまま復元完了を待っています。",
            isCancellationAvailable: true
        )
    )

    /// archived復元を取り消し、復元待ちへ戻った状態です。
    static let restoreCancelled = VehicleRegistrationPresentationState.archivedRestoreRequired(
        candidate(
            lifecycle: .archived,
            lifecycleRevision: 8,
            title: "車両の復元を取り消しました",
            message: "保持済みScanとarchived車両は削除していません。",
            maskedIdentifier: "•••• CANCEL-24Z",
            vehicleDisplayName: "Preview Cancelled Restore Vehicle",
            identifier: "fixture-cancelled-restore"
        )
    )

    /// archived復元時にlifecycle revision競合を検出した状態です。
    static let restoreLifecycleRevisionConflict = VehicleRegistrationPresentationState.conflict(
        display(
            title: "車両の状態が更新されています",
            message: "復元開始時のrevisionと現在のlifecycle revisionが一致しません。",
            unavailableReason: "車両状態を再確認してから復元候補を評価してください。",
            actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-restore-revision-conflict")
        )
    )

    /// archived復元が失敗し、復元待ちへ戻った状態です。
    static let restoreFailed = VehicleRegistrationPresentationState.archivedRestoreRequired(
        candidate(
            lifecycle: .archived,
            lifecycleRevision: 8,
            title: "車両を復元できませんでした",
            message: "保持済みScanとarchived車両を維持したまま再試行できます。",
            maskedIdentifier: "•••• RETRY-24Z",
            vehicleDisplayName: "Preview Failed Restore Vehicle",
            identifier: "fixture-failed-restore"
        )
    )

    /// 複数候補または識別衝突のConflict状態です。
    static let conflict = VehicleRegistrationPresentationState.conflict(
        display(
            title: "車両候補を確定できません",
            message: "複数の架空候補が一致したため、自動解決しません。",
            unavailableReason: "競合内容の確認が必要です。",
            actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-conflict")
        )
    )

    /// 新規登録確認が可能な状態です。
    static let registrationReady = VehicleRegistrationPresentationState.registrationReady(
        display(
            title: "新しい車両を登録できます",
            message: "mask済み識別結果を確認してください。",
            maskedIdentifier: "•••• READY-24Z",
            actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-registration")
        )
    )

    /// 新規車両の登録処理中で取消不能な状態です。
    static let registering = VehicleRegistrationPresentationState.registering(
        display(
            title: "車両を登録しています",
            message: "commit境界を越えたため、この操作は取り消せません。",
            maskedIdentifier: "•••• SAVING-24Z",
            progress: 0.8,
            actionDisabledReason: "登録commit後の取消しはできません。"
        )
    )

    /// 車両登録とSession所属が完了した状態です。
    static let registered = VehicleRegistrationPresentationState.registered(
        VehicleRegistrationRegisteredPresentation(
            sessionBindingState: .bound,
            display: display(
                title: "車両を登録しました",
                message: "現在Sessionの所属も確定しています。",
                maskedIdentifier: "•••• BOUND-24Z",
                vehicleDisplayName: "Preview Registered Vehicle",
                sessionSummary: "Sessionは登録車両へ所属済みです。",
                actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-bound-session")
            )
        )
    )

    /// 車両登録済みでSession所属だけが保留中の状態です。
    static let sessionBindingPending = VehicleRegistrationPresentationState.registered(
        VehicleRegistrationRegisteredPresentation(
            sessionBindingState: .pending,
            display: display(
                title: "車両登録済み・Session所属待ち",
                message: "車両登録は保持されています。Session所属だけを再試行できます。",
                maskedIdentifier: "•••• PENDING-24Z",
                vehicleDisplayName: "Preview Pending Vehicle",
                sessionSummary: "Sessionは未割当で、所属再試行を待っています。",
                actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-pending-session")
            )
        )
    )

    /// Production依存が利用不能なblocked状態です。
    static let blocked = VehicleRegistrationPresentationState.blocked(
        display(
            title: "車両登録は利用できません",
            message: "必要なProduction依存が未接続です。",
            unavailableReason: "安全な通信処理を開始できません。",
            actionDisabledReason: "接続機能が未実装です。"
        )
    )

    /// 現在attemptの終端失敗状態です。
    static let failed = VehicleRegistrationPresentationState.failed(
        display(
            title: "車両登録を完了できませんでした",
            message: "現在の試行は終了しました。保持済み情報は削除しません。",
            unavailableReason: "架空の終端エラーです。",
            actionIdentifier: VehicleRegistrationPresentationIdentifier("fixture-failed-session")
        )
    )

    /// 必須fixtureをシナリオごとに一覧で返します。
    static let allStates: [VehicleRegistrationPresentationState] = [
        disconnected,
        connecting,
        adapterChecking,
        identifying,
        identificationUnavailable,
        duplicateActive,
        duplicateArchived,
        archivedRestoreRequired,
        restoringArchivedVehicle,
        restoreCancelled,
        restoreLifecycleRevisionConflict,
        restoreFailed,
        conflict,
        registrationReady,
        registering,
        registered,
        sessionBindingPending,
        blocked,
        failed
    ]

    /// UIテスト用の安定名から個別fixtureを返します。
    /// - Parameter name: UIテストのlaunch environmentで指定するfixture名。
    /// - Returns: 対応するfixture。未知の名前では`nil`。
    static func state(named name: String) -> VehicleRegistrationPresentationState? {
        switch name {
        case "blocked":
            blocked
        case "no-identifier":
            identificationUnavailable
        case "duplicate-active":
            duplicateActive
        case "duplicate-archived":
            duplicateArchived
        case "restore-required":
            archivedRestoreRequired
        case "disconnected":
            disconnected
        case "adapter-checking":
            adapterChecking
        case "restoring-archived":
            restoringArchivedVehicle
        case "restore-cancelled":
            restoreCancelled
        case "restore-revision-conflict":
            restoreLifecycleRevisionConflict
        case "restore-failed":
            restoreFailed
        case "conflict":
            conflict
        case "registration-ready":
            registrationReady
        case "binding-pending":
            sessionBindingPending
        default:
            nil
        }
    }

    /// archivedまたはactive候補の安全なfixtureを生成します。
    /// - Parameters:
    ///   - lifecycle: 候補のライフサイクル状態。
    ///   - lifecycleRevision: 候補の架空revision。
    ///   - title: 状態見出し。
    ///   - message: 状態説明。
    ///   - maskedIdentifier: 架空のmask済み識別子。
    ///   - vehicleDisplayName: 架空の車両表示名。
    ///   - identifier: fixture専用の不透明参照値。
    /// - Returns: 機密情報を含まない候補fixture。
    private static func candidate(
        lifecycle: VehicleRegistrationDuplicateCandidate.Lifecycle,
        lifecycleRevision: Int,
        title: String,
        message: String,
        maskedIdentifier: String,
        vehicleDisplayName: String,
        identifier: String
    ) -> VehicleRegistrationDuplicateCandidate {
        VehicleRegistrationDuplicateCandidate(
            lifecycle: lifecycle,
            lifecycleRevision: lifecycleRevision,
            display: display(
                title: title,
                message: message,
                maskedIdentifier: maskedIdentifier,
                vehicleDisplayName: vehicleDisplayName,
                actionIdentifier: VehicleRegistrationPresentationIdentifier(identifier)
            )
        )
    }

    /// 共通の安全な表示値を生成します。
    /// - Parameters:
    ///   - title: 状態見出し。
    ///   - message: 状態説明。
    ///   - maskedIdentifier: 架空のmask済み識別子。
    ///   - vehicleDisplayName: 架空の車両表示名。
    ///   - adapterDisplayName: 架空のAdapter表示名。
    ///   - progress: 0から1の進捗。
    ///   - sessionSummary: Session保持状態の説明。
    ///   - unavailableReason: 安定した利用不能理由。
    ///   - actionDisabledReason: Actionを実行できない理由。
    ///   - isCancellationAvailable: 現在の処理を安全に取り消せるかどうか。
    ///   - actionIdentifier: fixture専用の不透明参照。
    /// - Returns: 機密情報を含まない表示専用値。
    private static func display(
        title: String,
        message: String,
        maskedIdentifier: String? = nil,
        vehicleDisplayName: String? = nil,
        adapterDisplayName: String? = nil,
        progress: Double? = nil,
        sessionSummary: String = "Sessionは車両未割当のまま保持されています。",
        unavailableReason: String? = nil,
        actionDisabledReason: String? = nil,
        isCancellationAvailable: Bool = false,
        actionIdentifier: VehicleRegistrationPresentationIdentifier? = nil
    ) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: title,
            message: message,
            maskedIdentifier: maskedIdentifier,
            vehicleDisplayName: vehicleDisplayName,
            adapterDisplayName: adapterDisplayName,
            progress: progress,
            sessionSummary: sessionSummary,
            unavailableReason: unavailableReason,
            actionDisabledReason: actionDisabledReason,
            isCancellationAvailable: isCancellationAvailable,
            revision: VehicleRegistrationPresentationRevision(100),
            actionIdentifier: actionIdentifier
        )
    }
}
#endif
