/// 承認済みUSB Descriptorに一致するserial endpointだけを解決する能力です。
nonisolated protocol USBSerialEndpointLocating: Sendable {
    /// Descriptorが完全一致したcallout endpointを列挙します。
    /// - Returns: Endpoint秘密値をPlatformへ公開しないDomain transport endpoint配列。
    /// - Throws: OSのUSB Registryを安全に読めない場合。
    func locateApprovedEndpoints() throws -> [TransportEndpoint]
}
