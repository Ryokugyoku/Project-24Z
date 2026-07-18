import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// 登録、Snapshot境界、冪等性、rollback、lifecycle競合、再起動を検証します。
@Suite(.serialized)
struct GRDBVehicleIdentityRepositoryTests {
    /// 新規aggregateを一括保存し、Digest候補と親子件数を読戻します。
    @Test
    func registersAndReadsBackWholeAggregate() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try makeStore(fixture)
        let request = VehicleIdentityTestFixtures.registrationRequest()

        guard case .registered(let vehicle) = try store.repository.register(request) else {
            Issue.record("New vehicle must be active")
            return
        }
        #expect(vehicle.vehicleID == request.proposedVehicleID)
        #expect(vehicle.lifecycle == .active)
        let candidate = try store.repository.findCandidate(
            kind: .vin,
            lookupDigest: request.identifiers[0].lookupDigest
        )
        #expect(candidate?.vehicleID == vehicle.vehicleID)
        let counts = try store.databasePool.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicles")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicle_identification_scans")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM ecu_observations")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM ecu_identification_values")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicle_identifiers")!
            )
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 1)
        #expect(counts.3 == 1)
        #expect(counts.4 == 1)
    }

    /// 同一final Snapshotは二重行を作らず、内容差異はConflictにします。
    @Test
    func connectionBoundaryIsIdempotentOnlyForExactSnapshot() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try makeStore(fixture)
        let request = VehicleIdentityTestFixtures.registrationRequest()
        _ = try store.repository.register(request)
        _ = try store.repository.register(request)

        let changed = VehicleRegistrationRequest(
            proposedVehicleID: request.proposedVehicleID,
            encryptedDisplayName: request.encryptedDisplayName,
            identifiers: request.identifiers,
            scan: VehicleIdentificationScanSnapshot(
                scanID: request.scan.scanID,
                obdConnectionID: request.scan.obdConnectionID,
                transportKind: request.scan.transportKind,
                diagnosticProtocolKind: request.scan.diagnosticProtocolKind,
                adapterReferenceID: request.scan.adapterReferenceID,
                decoderVersion: "decoder-v2",
                normalizationVersion: request.scan.normalizationVersion,
                status: request.scan.status,
                decodeState: request.scan.decodeState,
                identityValidationState: request.scan.identityValidationState,
                terminationReasonCode: request.scan.terminationReasonCode,
                startedAt: request.scan.startedAt,
                finishedAt: request.scan.finishedAt,
                observations: request.scan.observations
            ),
            deviceID: request.deviceID,
            recordedAt: request.recordedAt
        )
        #expect(throws: VehiclePersistenceError.idempotencyConflict) {
            try store.repository.register(changed)
        }
        let scanCount = try store.databasePool.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM vehicle_identification_scans")
        }
        #expect(scanCount == 1)
    }

    /// standalone経路がvalid ScanをNULL vehicleへ降格保存しないことを検証します。
    @Test
    func standaloneAppendRejectsValidScan() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try makeStore(fixture)
        let request = VehicleIdentityTestFixtures.registrationRequest()
        #expect(throws: VehiclePersistenceError.invalidRequest) {
            try store.repository.appendTerminalScan(
                request.scan,
                vehicleID: nil,
                deviceID: request.deviceID,
                recordedAt: request.recordedAt
            )
        }
        let count = try store.databasePool.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM vehicle_identification_scans")
        }
        #expect(count == 0)
    }

    /// 子行Unique違反時に親VehicleとScanを含むtransaction全体をrollbackします。
    @Test
    func childConstraintFailureRollsBackRegistration() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let store = try makeStore(fixture)
        let original = VehicleIdentityTestFixtures.registrationRequest()
        let first = original.scan.observations[0]
        let duplicateAddress = ECUObservationSnapshot(
            observationID: UUID(),
            ordinal: 1,
            addressFormat: first.addressFormat,
            responderAddress: first.responderAddress,
            values: []
        )
        let failing = VehicleRegistrationRequest(
            proposedVehicleID: original.proposedVehicleID,
            encryptedDisplayName: nil,
            identifiers: original.identifiers,
            scan: VehicleIdentificationScanSnapshot(
                scanID: original.scan.scanID,
                obdConnectionID: original.scan.obdConnectionID,
                transportKind: original.scan.transportKind,
                diagnosticProtocolKind: original.scan.diagnosticProtocolKind,
                adapterReferenceID: original.scan.adapterReferenceID,
                decoderVersion: original.scan.decoderVersion,
                normalizationVersion: original.scan.normalizationVersion,
                status: .completed,
                decodeState: .decoded,
                identityValidationState: .valid,
                terminationReasonCode: nil,
                startedAt: original.scan.startedAt,
                finishedAt: original.scan.finishedAt,
                observations: [first, duplicateAddress]
            ),
            deviceID: original.deviceID,
            recordedAt: original.recordedAt
        )

        #expect(throws: VehiclePersistenceError.conflict) {
            try store.repository.register(failing)
        }
        let counts = try store.databasePool.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicles")!,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicle_identification_scans")!
            )
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    /// active／archived一覧を分離し、競合復元を拒否して正しい復元を再起動後も保持します。
    @Test
    func archiveRestoreUsesLifecycleRevisionAndSurvivesRestart() throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        var store: GRDBVehicleIdentityStore? = try makeStore(fixture)
        let request = VehicleIdentityTestFixtures.registrationRequest()
        guard case .registered(let registered) = try store!.repository.register(request) else {
            Issue.record("Registration failed")
            return
        }
        let archived = try store!.repository.archiveVehicle(
            vehicleID: registered.vehicleID,
            expectedLifecycleRevision: registered.lifecycleRevision,
            deviceID: request.deviceID,
            updatedAt: request.recordedAt.addingTimeInterval(1)
        )
        #expect(try store!.repository.fetchVehicles(lifecycle: .active).isEmpty)
        #expect(try store!.repository.fetchVehicles(lifecycle: .archived).map(\.vehicleID) == [registered.vehicleID])
        #expect(throws: VehiclePersistenceError.conflict) {
            try store!.repository.restoreArchivedVehicle(
                vehicleID: registered.vehicleID,
                expectedLifecycleRevision: archived.lifecycleRevision - 1,
                identifierKind: .vin,
                lookupDigest: request.identifiers[0].lookupDigest,
                deviceID: request.deviceID,
                updatedAt: request.recordedAt.addingTimeInterval(2)
            )
        }
        let restored = try store!.repository.restoreArchivedVehicle(
            vehicleID: registered.vehicleID,
            expectedLifecycleRevision: archived.lifecycleRevision,
            identifierKind: .vin,
            lookupDigest: request.identifiers[0].lookupDigest,
            deviceID: request.deviceID,
            updatedAt: request.recordedAt.addingTimeInterval(3)
        )
        #expect(restored.lifecycle == .active)

        store = nil
        let reopened = try makeStore(fixture)
        let reread = try reopened.repository.findCandidate(
            kind: .vin,
            lookupDigest: request.identifiers[0].lookupDigest
        )
        #expect(reread?.lifecycle == .active)
        #expect(reread?.lifecycleRevision == archived.lifecycleRevision + 1)
    }

    /// fixture用Storeを起動します。
    /// - Parameter fixture: テスト専用DBパス。
    /// - Returns: 利用可能GRDB Store。
    /// - Throws: 起動がunavailableならエラー。
    private func makeStore(_ fixture: TemporaryVehicleDatabase) throws -> GRDBVehicleIdentityStore {
        guard case .available(let store) = GRDBVehicleIdentityStore.open(
            at: fixture.url,
            userScopeID: VehicleIdentityTestFixtures.scopeID,
            activeDigestKeyVersion: 1,
            createdAt: VehicleIdentityTestFixtures.recordedAt
        ) else {
            throw VehiclePersistenceError.unavailable
        }
        return store
    }
}
