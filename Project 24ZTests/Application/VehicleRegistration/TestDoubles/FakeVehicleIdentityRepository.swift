import Foundation
@testable import Project_24Z

/// Application登録順序、競合、結果不明、復元を制御するFake Repositoryです。
final class FakeVehicleIdentityRepository: VehicleIdentityRepository {
    /// Digestごとの候補です。
    var candidates: [Data: VehicleIdentity] = [:]
    /// registerごとに返す結果です。
    var registrationResults: [Result<VehicleRegistrationResult, VehiclePersistenceError>] = []
    /// 復元を失敗させるErrorです。
    var restoreError: VehiclePersistenceError?
    /// register呼出し回数です。
    private(set) var registrationCallCount = 0
    /// 復元呼出し回数です。
    private(set) var restoreCallCount = 0

    /// lifecycle別候補を返します。
    func fetchVehicles(lifecycle: VehicleIdentity.Lifecycle) throws -> [VehicleIdentity] {
        candidates.values.filter { $0.lifecycle == lifecycle }
    }

    /// Digest候補を返します。
    func findCandidate(kind: VehicleIdentifierEvidence.Kind, lookupDigest: Data) throws -> VehicleIdentity? {
        candidates[lookupDigest]
    }

    /// 設定済み結果を順に返します。
    func register(_ request: VehicleRegistrationRequest) throws -> VehicleRegistrationResult {
        registrationCallCount += 1
        guard !registrationResults.isEmpty else { throw VehiclePersistenceError.unavailable }
        let result = try registrationResults.removeFirst().get()
        let vehicle: VehicleIdentity
        switch result {
        case .registered(let value), .archivedRestoreRequired(let value):
            vehicle = value
        }
        for evidence in request.identifiers where candidates[evidence.lookupDigest] == nil {
            candidates[evidence.lookupDigest] = vehicle
        }
        return result
    }

    /// non-valid Scan追加は本Fakeでは利用しません。
    func appendTerminalScan(
        _ snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws {}

    /// active車両をarchivedへ変換します。
    func archiveVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        guard let current = candidates.values.first(where: { $0.vehicleID == vehicleID && $0.lifecycleRevision == expectedLifecycleRevision }) else {
            throw VehiclePersistenceError.conflict
        }
        return copy(current, lifecycle: .archived, revision: expectedLifecycleRevision + 1)
    }

    /// archived車両をactiveへ変換し、Digest候補も更新します。
    func restoreArchivedVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        identifierKind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        restoreCallCount += 1
        if let restoreError { throw restoreError }
        guard let current = candidates[lookupDigest],
              current.vehicleID == vehicleID,
              current.lifecycle == .archived,
              current.lifecycleRevision == expectedLifecycleRevision else {
            throw VehiclePersistenceError.conflict
        }
        let restored = copy(current, lifecycle: .active, revision: expectedLifecycleRevision + 1)
        candidates[lookupDigest] = restored
        return restored
    }

    /// Lifecycleだけを変えたFake車両を作ります。
    private func copy(
        _ vehicle: VehicleIdentity,
        lifecycle: VehicleIdentity.Lifecycle,
        revision: Int
    ) -> VehicleIdentity {
        VehicleIdentity(
            userScopeID: vehicle.userScopeID,
            vehicleID: vehicle.vehicleID,
            encryptedDisplayName: vehicle.encryptedDisplayName,
            lifecycle: lifecycle,
            recordRevision: vehicle.recordRevision + 1,
            displayNameRevision: vehicle.displayNameRevision,
            lifecycleRevision: revision,
            archivedAt: lifecycle == .archived ? .now : nil,
            createdAt: vehicle.createdAt,
            updatedAt: .now
        )
    }
}
