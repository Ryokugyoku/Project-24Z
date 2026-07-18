/// Application内部のAction参照だけに使用する不透明な識別子です。
struct VehicleRegistrationPresentationIdentifier: Equatable, Hashable, Sendable {
    /// Application内部で参照を照合する値です。画面表示には使用しません。
    private let rawValue: String

    /// 不透明な参照値を生成します。
    /// - Parameter rawValue: Application内部だけで使用する参照値。
    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
