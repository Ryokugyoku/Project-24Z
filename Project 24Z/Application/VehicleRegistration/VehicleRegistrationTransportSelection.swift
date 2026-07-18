/// 接続開始Actionだけに使用する不透明なTransport選択値です。
struct VehicleRegistrationTransportSelection: Equatable, Hashable, Sendable {
    /// Application内部だけでTransport候補を照合する値です。
    private let rawValue: String

    /// 不透明なTransport選択値を生成します。
    /// - Parameter rawValue: Application内部だけで使用する照合値。
    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
