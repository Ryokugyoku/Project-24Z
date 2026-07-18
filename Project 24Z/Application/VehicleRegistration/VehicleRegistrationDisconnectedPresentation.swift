/// 接続前の安全な表示値と選択可能候補をまとめます。
struct VehicleRegistrationDisconnectedPresentation: Equatable, Sendable {
    /// 接続前状態の安全な表示値です。
    let display: VehicleRegistrationDisplayValues

    /// Endpoint秘密IDや具象Transportを含まない接続候補です。
    let transportOptions: [VehicleRegistrationTransportOption]

    /// 接続前Presentationを生成します。
    /// - Parameters:
    ///   - display: 接続前状態の安全な表示値。
    ///   - transportOptions: 選択可能な安全な接続候補。
    init(
        display: VehicleRegistrationDisplayValues,
        transportOptions: [VehicleRegistrationTransportOption]
    ) {
        self.display = display
        self.transportOptions = transportOptions
    }
}
