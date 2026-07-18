/// 車両登録画面に表示した状態の世代を識別します。
struct VehicleRegistrationPresentationRevision: Equatable, Hashable, Sendable {
    /// 世代を比較するための単調増加値です。
    let value: Int

    /// 表示世代を生成します。
    /// - Parameter value: 世代を比較するための値。
    init(_ value: Int) {
        self.value = value
    }
}
