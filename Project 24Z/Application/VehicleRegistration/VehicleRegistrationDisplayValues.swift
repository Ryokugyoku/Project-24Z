/// 車両登録画面へ公開する、機密情報を含まない表示専用値です。
struct VehicleRegistrationDisplayValues: Equatable, Sendable {
    /// 状態の見出しです。
    let title: String

    /// 状態を説明する本文です。
    let message: String

    /// mask済みの識別子です。
    let maskedIdentifier: String?

    /// 利用者向けの車両表示名です。
    let vehicleDisplayName: String?

    /// 機密IDを含まないAdapter表示名です。
    let adapterDisplayName: String?

    /// 完了率を0から1で表す進捗です。
    let progress: Double?

    /// Sessionを保持している状態の説明です。
    let sessionSummary: String

    /// blockedまたは利用不能である安定理由です。
    let unavailableReason: String?

    /// Actionを実行できない理由です。
    let actionDisabledReason: String?

    /// 現在の処理を安全に取り消せる境界内かを示します。
    let isCancellationAvailable: Bool

    /// 現在表示している状態の世代です。
    let revision: VehicleRegistrationPresentationRevision

    /// 状態固有Actionが参照する不透明値です。
    let actionIdentifier: VehicleRegistrationPresentationIdentifier?

    /// 表示専用値を生成します。
    /// - Parameters:
    ///   - title: 状態の見出し。
    ///   - message: 状態を説明する本文。
    ///   - maskedIdentifier: mask済み識別子。
    ///   - vehicleDisplayName: 利用者向け車両表示名。
    ///   - adapterDisplayName: 機密IDを含まないAdapter表示名。
    ///   - progress: 0から1の進捗。
    ///   - sessionSummary: Session保持状態の説明。
    ///   - unavailableReason: 利用不能である安定理由。
    ///   - actionDisabledReason: Actionを実行できない理由。
    ///   - isCancellationAvailable: 現在の処理を取り消せるかどうか。
    ///   - revision: 現在表示している状態の世代。
    ///   - actionIdentifier: 状態固有Actionが参照する不透明値。
    init(
        title: String,
        message: String,
        maskedIdentifier: String? = nil,
        vehicleDisplayName: String? = nil,
        adapterDisplayName: String? = nil,
        progress: Double? = nil,
        sessionSummary: String,
        unavailableReason: String? = nil,
        actionDisabledReason: String? = nil,
        isCancellationAvailable: Bool = false,
        revision: VehicleRegistrationPresentationRevision,
        actionIdentifier: VehicleRegistrationPresentationIdentifier? = nil
    ) {
        self.title = title
        self.message = message
        self.maskedIdentifier = maskedIdentifier
        self.vehicleDisplayName = vehicleDisplayName
        self.adapterDisplayName = adapterDisplayName
        self.progress = progress
        self.sessionSummary = sessionSummary
        self.unavailableReason = unavailableReason
        self.actionDisabledReason = actionDisabledReason
        self.isCancellationAvailable = isCancellationAvailable
        self.revision = revision
        self.actionIdentifier = actionIdentifier
    }
}
