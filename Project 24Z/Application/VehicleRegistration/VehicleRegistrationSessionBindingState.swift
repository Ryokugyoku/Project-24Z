/// 登録済み車両と現在Sessionの所属状態を表します。
enum VehicleRegistrationSessionBindingState: Equatable, Sendable {
    /// Session所属が確定しています。
    case bound

    /// 車両登録は確定していますがSession所属の再試行が必要です。
    case pending
}
