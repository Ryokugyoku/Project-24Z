/// 取得Session中に変更できないAdapter役割です。
nonisolated enum CommunicationRole: String, Equatable, Sendable {
    case primaryOBD = "primary_obd"
    case secondaryRawCAN = "secondary_raw_can"
}
