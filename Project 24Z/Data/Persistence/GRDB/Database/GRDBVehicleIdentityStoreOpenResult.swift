/// Vehicle Identity Storeの起動結果を明示的に表します。
enum GRDBVehicleIdentityStoreOpenResult {
    /// Migrationと起動時検査を完了したStoreです。
    case available(GRDBVehicleIdentityStore)
    /// 元DBを保持したまま停止した結果です。
    case unavailable(VehicleIdentityStoreUnavailable)
}
