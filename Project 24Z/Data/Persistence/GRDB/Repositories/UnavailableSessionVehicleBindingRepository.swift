import Foundation

/// Acquisition Session schema未導入中にProduction bindingを明示的に停止します。
struct UnavailableSessionVehicleBindingRepository: SessionVehicleBindingRepository {
    /// Production未接続境界を構成します。
    init() {}

    /// Session SoRとMigrationが未導入のため、車両登録済みデータを変更せず停止します。
    /// - Parameters:
    ///   - sessionID: 未使用のSession UUID。
    ///   - vehicleID: 削除・変更しない登録済み車両UUID。
    ///   - expectedSessionRevision: 未使用のSession Revision。
    ///   - expectedVehicleLifecycleRevision: 未使用のLifecycle Revision。
    /// - Throws: 常に`VehiclePersistenceError.unavailable`。
    func bind(
        sessionID: UUID,
        vehicleID: UUID,
        expectedSessionRevision: Int,
        expectedVehicleLifecycleRevision: Int
    ) throws {
        throw VehiclePersistenceError.unavailable
    }
}
