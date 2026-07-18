/// 再接続後の車両識別をRuntime外のVehicle Identity境界から受け取る結果です。
nonisolated enum VehicleReidentificationResult: Equatable, Sendable {
    case sameVehicleConfirmed
    case differentVehicleConfirmed
    case unavailable
}
