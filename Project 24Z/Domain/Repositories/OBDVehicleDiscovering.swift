/// 承認済みread-only OBD Requestだけで車両識別とPID値を取得する境界です。
nonisolated protocol OBDVehicleDiscovering: Sendable {
    /// Adapter確認、車両VIN取得、最小PID probeを直列実行して必ずTransportを閉じます。
    /// - Returns: 一意なVINと成功PID値を持つ終端Snapshot。
    /// - Throws: Endpoint、identity、timeout、応答形状、一意性のいずれかが不正な場合。
    func discoverVehicle() async throws -> OBDVehicleDiscoverySnapshot

    /// 進行中のTransportを閉じ、後続Requestを送信不能にします。
    func cancel() async
}
