import Foundation

/// 車両、識別子、Scan、ECU観測、識別値を一貫したtransactionで扱う境界です。
protocol VehicleIdentityRepository {
    /// activeとarchivedを混在させず車両一覧を取得します。
    /// - Parameter lifecycle: 取得するライフサイクル状態。
    /// - Returns: 指定状態の車両だけを更新日時降順で返します。
    /// - Throws: DB利用不能または整合性違反時の安定エラー。
    func fetchVehicles(lifecycle: VehicleIdentity.Lifecycle) throws -> [VehicleIdentity]

    /// Digestに一致する候補を一意に取得します。
    /// - Parameters:
    ///   - kind: 識別子種別。
    ///   - lookupDigest: 平文を含まない32 byte Digest。
    /// - Returns: 一致しない場合はnil、一意な場合はその車両。
    /// - Throws: 複数一致またはDB利用不能時の安定エラー。
    func findCandidate(
        kind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data
    ) throws -> VehicleIdentity?

    /// 新規・active一致・archived一致を一transactionで再判定して保存します。
    /// - Parameter request: 暗号・Digest準備済みの最終Snapshot要求。
    /// - Returns: active登録結果または明示復元待ち結果。
    /// - Throws: 制約、競合、利用不能時の安定エラー。途中書込みはrollbackされます。
    func register(_ request: VehicleRegistrationRequest) throws -> VehicleRegistrationResult

    /// validではない一接続の終端Snapshotを一件だけ追記します。
    /// - Parameters:
    ///   - snapshot: invalid、unavailable、incomplete、failedの最終Snapshot。
    ///   - vehicleID: 確実に関連付けられる登録済み車両。未登録ならnil。
    ///   - deviceID: 記録端末UUID。
    ///   - recordedAt: DB記録日時。
    /// - Throws: valid Snapshot、重複差異、制約違反、利用不能時の安定エラー。
    func appendTerminalScan(
        _ snapshot: VehicleIdentificationScanSnapshot,
        vehicleID: UUID?,
        deviceID: UUID,
        recordedAt: Date
    ) throws

    /// active車両を期待Lifecycle Revisionでアーカイブします。
    /// - Parameters:
    ///   - vehicleID: 対象の内部車両UUID。
    ///   - expectedLifecycleRevision: 呼び出し側が確認したRevision。
    ///   - deviceID: 更新端末UUID。
    ///   - updatedAt: 更新日時。
    /// - Returns: 読戻し検証済みのarchived車両。
    /// - Throws: 状態変化、Revision競合、利用不能時の安定エラー。
    func archiveVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity

    /// archived車両を期待Lifecycle Revisionで明示復元します。
    /// - Parameters:
    ///   - vehicleID: 復元対象の内部車両UUID。
    ///   - expectedLifecycleRevision: UIが確認したRevision。
    ///   - identifierKind: 復元根拠の識別子種別。
    ///   - lookupDigest: 復元根拠のDigest。
    ///   - deviceID: 更新端末UUID。
    ///   - updatedAt: 更新日時。
    /// - Returns: 読戻し検証済みのactive車両。
    /// - Throws: 状態変化、Revision変化、根拠不一致、利用不能時の安定エラー。
    func restoreArchivedVehicle(
        vehicleID: UUID,
        expectedLifecycleRevision: Int,
        identifierKind: VehicleIdentifierEvidence.Kind,
        lookupDigest: Data,
        deviceID: UUID,
        updatedAt: Date
    ) throws -> VehicleIdentity
}
