import Foundation
@testable import Project_24Z

/// binding成功／失敗と呼出し回数を記録するFakeです。
final class RecordingSessionVehicleBindingRepository: SessionVehicleBindingRepository {
    /// 次のbinding Errorです。
    var error: VehiclePersistenceError?
    /// binding呼出し回数です。
    private(set) var callCount = 0
    /// 最後に所属させた車両UUIDです。
    private(set) var lastVehicleID: UUID?

    /// bindingを記録し、設定Errorまたは成功を返します。
    func bind(
        sessionID: UUID,
        vehicleID: UUID,
        expectedSessionRevision: Int,
        expectedVehicleLifecycleRevision: Int
    ) throws {
        callCount += 1
        lastVehicleID = vehicleID
        if let error { throw error }
    }
}
