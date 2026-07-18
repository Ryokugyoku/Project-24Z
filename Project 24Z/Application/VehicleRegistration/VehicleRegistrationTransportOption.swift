/// disconnected画面へ公開する安全なTransport／Adapter候補です。
struct VehicleRegistrationTransportOption: Equatable, Sendable {
    /// 接続開始時にApplicationへ返す不透明なTransport選択値です。
    let transportSelection: VehicleRegistrationTransportSelection

    /// Adapter選択ActionでApplicationへ返す不透明な候補tokenです。
    let adapterSelection: VehicleRegistrationPresentationIdentifier

    /// Endpoint秘密IDを含まない候補表示名です。
    let displayName: String

    /// 現在選択済みの候補かを示します。
    let isSelected: Bool

    /// 安全なTransport／Adapter候補を生成します。
    /// - Parameters:
    ///   - transportSelection: 接続開始用の不透明なTransport選択値。
    ///   - adapterSelection: Adapter選択用の不透明な候補token。
    ///   - displayName: Endpoint秘密IDを含まない表示名。
    ///   - isSelected: 現在選択済みかどうか。
    init(
        transportSelection: VehicleRegistrationTransportSelection,
        adapterSelection: VehicleRegistrationPresentationIdentifier,
        displayName: String,
        isSelected: Bool
    ) {
        self.transportSelection = transportSelection
        self.adapterSelection = adapterSelection
        self.displayName = displayName
        self.isSelected = isSelected
    }
}
