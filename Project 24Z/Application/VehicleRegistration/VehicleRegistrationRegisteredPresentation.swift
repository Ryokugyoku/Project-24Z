/// 登録済み車両とSession所属の安全な表示状態です。
struct VehicleRegistrationRegisteredPresentation: Equatable, Sendable {
    /// Session所属状態です。
    let sessionBindingState: VehicleRegistrationSessionBindingState

    /// 登録済み車両の安全な表示値です。
    let display: VehicleRegistrationDisplayValues

    /// 登録済み表示状態を生成します。
    /// - Parameters:
    ///   - sessionBindingState: Session所属状態。
    ///   - display: 登録済み車両の安全な表示値。
    init(
        sessionBindingState: VehicleRegistrationSessionBindingState,
        display: VehicleRegistrationDisplayValues
    ) {
        self.sessionBindingState = sessionBindingState
        self.display = display
    }
}
