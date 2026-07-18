import Foundation
import Testing
@testable import Project_24Z

/// 登録transactionから分離されたSession binding境界を検証します。
struct SessionVehicleBindingRepositoryTests {
    /// Fake bindingは同一車両への再試行を冪等成功させ、別車両への付替えを拒否します。
    @Test
    func fakeBindingIsSeparateIdempotentAndConflictSafe() throws {
        let sessionID = UUID()
        let vehicleID = UUID()
        let otherVehicleID = UUID()
        let repository = FakeSessionVehicleBindingRepository(
            activeVehicleRevisions: [vehicleID: 4, otherVehicleID: 1]
        )
        repository.seed(.init(sessionID: sessionID, vehicleID: nil, revision: 2, isFinalized: false))

        try repository.bind(
            sessionID: sessionID,
            vehicleID: vehicleID,
            expectedSessionRevision: 2,
            expectedVehicleLifecycleRevision: 4
        )
        try repository.bind(
            sessionID: sessionID,
            vehicleID: vehicleID,
            expectedSessionRevision: 2,
            expectedVehicleLifecycleRevision: 4
        )
        #expect(repository.state(sessionID: sessionID)?.revision == 3)
        #expect(throws: VehiclePersistenceError.conflict) {
            try repository.bind(
                sessionID: sessionID,
                vehicleID: otherVehicleID,
                expectedSessionRevision: 3,
                expectedVehicleLifecycleRevision: 1
            )
        }
    }

    /// Production用blocked境界は登録済みVehicleへ副作用を与えず明示的に停止します。
    @Test
    func productionBindingRemainsUnavailable() {
        let repository = UnavailableSessionVehicleBindingRepository()
        #expect(throws: VehiclePersistenceError.unavailable) {
            try repository.bind(
                sessionID: UUID(),
                vehicleID: UUID(),
                expectedSessionRevision: 1,
                expectedVehicleLifecycleRevision: 1
            )
        }
    }
}
