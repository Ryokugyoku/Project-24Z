import Foundation
import Testing
@testable import Project_24Z

/// 認証scopeとCrypto未接続時のVehicle Identity停止境界を検証します。
struct UnavailableVehicleIdentityRepositoryTests {
    /// 読取りとLifecycle変更を成功扱いせず既存データへ触れないことを検証します。
    @Test
    func allReachableOperationsRemainUnavailable() {
        let repository = UnavailableVehicleIdentityRepository()

        #expect(throws: VehiclePersistenceError.unavailable) {
            try repository.fetchVehicles(lifecycle: .active)
        }
        #expect(throws: VehiclePersistenceError.unavailable) {
            try repository.archiveVehicle(
                vehicleID: UUID(),
                expectedLifecycleRevision: 1,
                deviceID: UUID(),
                updatedAt: Date()
            )
        }
        #expect(throws: VehiclePersistenceError.unavailable) {
            try repository.restoreArchivedVehicle(
                vehicleID: UUID(),
                expectedLifecycleRevision: 1,
                identifierKind: .vin,
                lookupDigest: Data(repeating: 0, count: 32),
                deviceID: UUID(),
                updatedAt: Date()
            )
        }
    }
}
