import Foundation

/// 認証scopeとCrypto Hard Gate未達時にVehicle Identity書込みを拒否するProduction Repositoryです。
struct UnavailableVehicleIdentityRepository: VehicleIdentityRepository {
    /// Production用の非破壊停止Repositoryを構成します。
    init() {}

    /// DBを開かず車両一覧取得を拒否します。
    /// - Parameter lifecycle: 取得しないLifecycle。
    /// - Returns: この実装は一覧を返しません。
    /// - Throws: 常に`unavailable`。
    func fetchVehicles(lifecycle: VehicleIdentity.Lifecycle) throws -> [VehicleIdentity] {
        throw VehiclePersistenceError.unavailable
    }

    /// Digest照合を行わず拒否します。
    /// - Parameters:
    ///   - kind: 照合しないIdentifier kind。
    ///   - lookupDigest: 使用しないDigest。
    /// - Returns: この実装は候補を返しません。
    /// - Throws: 常に`unavailable`。
    func findCandidate(
        kind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data
    ) throws -> VehicleIdentity? {
        throw VehiclePersistenceError.unavailable
    }

    /// 登録要求を永続化せず拒否します。
    /// - Parameter request: 保存しない登録要求。
    /// - Returns: この実装は登録結果を返しません。
    /// - Throws: 常に`unavailable`。
    func register(_ request: VehicleRegistrationRequest) throws -> VehicleRegistrationResult {
        throw VehiclePersistenceError.unavailable
    }

    /// 終端Scanを永続化せず拒否します。
    /// - Parameters:
    ///   - snapshot: 保存しないSnapshot。
    ///   - vehicleID: 変更しない車両参照。
    ///   - deviceID: 使用しない端末参照。
    ///   - recordedAt: 使用しない記録日時。
    /// - Throws: 常に`unavailable`。
    func appendTerminalScan(
        _ snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws {
        throw VehiclePersistenceError.unavailable
    }

    /// active車両を変更せずアーカイブ要求を拒否します。
    /// - Parameters:
    ///   - vehicleID: 変更しない車両参照。
    ///   - expectedLifecycleRevision: 使用しない期待Revision。
    ///   - deviceID: 使用しない端末参照。
    ///   - updatedAt: 使用しない更新日時。
    /// - Returns: この実装は車両を返しません。
    /// - Throws: 常に`unavailable`。
    func archiveVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        throw VehiclePersistenceError.unavailable
    }

    /// archived車両を変更せず復元要求を拒否します。
    /// - Parameters:
    ///   - vehicleID: 変更しない車両参照。
    ///   - expectedLifecycleRevision: 使用しない期待Revision。
    ///   - identifierKind: 使用しないIdentifier kind。
    ///   - lookupDigest: 使用しないDigest。
    ///   - deviceID: 使用しない端末参照。
    ///   - updatedAt: 使用しない更新日時。
    /// - Returns: この実装は車両を返しません。
    /// - Throws: 常に`unavailable`。
    func restoreArchivedVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        identifierKind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity {
        throw VehiclePersistenceError.unavailable
    }
}
