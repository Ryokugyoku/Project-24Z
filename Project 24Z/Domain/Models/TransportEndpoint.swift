/// Transport上の一時的な到達先です。物理Adapterの恒久Identityではありません。
nonisolated struct TransportEndpoint: Equatable, Hashable, Sendable {
    /// Transportの種類です。種類間の成立性を推測で共有しません。
    enum Kind: String, Sendable { case usbSerial = "usb_serial"; case bluetoothLE = "bluetooth_le"; case bluetoothClassic = "bluetooth_classic"; case tcp }

    let identifier: String
    let kind: Kind
}
