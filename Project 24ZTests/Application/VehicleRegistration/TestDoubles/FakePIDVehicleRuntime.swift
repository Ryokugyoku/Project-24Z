import Foundation
@testable import Project_24Z

/// support探索とbatch fallbackを観測するactor Fakeです。
actor FakePIDVehicleRuntime: PIDVehicleRuntime {
    /// batch結果です。nilなら失敗します。
    var batchResponse: PIDPollingResponse?
    /// singleで呼ばれたIdentityです。
    private(set) var singleRequests: [PIDSignalIdentity] = []
    /// batchで呼ばれたIdentity集合です。
    private(set) var batchRequests: [[PIDSignalIdentity]] = []
    /// support探索結果です。
    var supportSnapshot: PIDSupportSnapshot?

    /// Fakeの結果を初期化します。
    /// - Parameters:
    ///   - batchResponse: batch結果。
    ///   - supportSnapshot: 探索結果。
    init(batchResponse: PIDPollingResponse? = nil, supportSnapshot: PIDSupportSnapshot? = nil) {
        self.batchResponse = batchResponse
        self.supportSnapshot = supportSnapshot
    }

    /// 設定済みsupport Snapshotを返します。
    func discoverSupport(
        catalog: PIDCatalogSnapshot,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) async throws -> PIDSupportSnapshot {
        guard let supportSnapshot else { throw VehiclePersistenceError.unavailable }
        return supportSnapshot
    }

    /// batch呼出しを記録し、設定結果または失敗を返します。
    func pollBatch(
        identities: [PIDSignalIdentity],
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse {
        batchRequests.append(identities)
        guard let batchResponse else { throw VehiclePersistenceError.unavailable }
        return batchResponse
    }

    /// single呼出しを記録してRaw保持結果を返します。
    func pollSingle(
        identity: PIDSignalIdentity,
        generation: ConnectionGeneration
    ) async throws -> PIDPollingResponse {
        singleRequests.append(identity)
        return PIDPollingResponse(
            requestKind: .single,
            identities: [identity],
            rawResponse: Data(identity.ecuSource),
            isUsable: true
        )
    }
}
