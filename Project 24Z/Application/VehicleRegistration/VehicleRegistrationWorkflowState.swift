import Foundation

/// Repository／Runtime接続をPlatform非依存で表すApplication状態です。
enum VehicleRegistrationWorkflowState: Equatable, Sendable {
    /// current接続がありません。
    case idle(revision: UInt64)
    /// current generation／attemptで識別中です。
    case identifying(generation: ConnectionGeneration, attemptID: UUID, revision: UInt64)
    /// 有効Identifierが既存車両へ一致せず登録確認待ちです。
    case registrationReady(VehicleRegistrationWorkflowContext, revision: UInt64)
    /// 一意なactive既存候補の確認待ちです。
    case activeDuplicate(VehicleRegistrationWorkflowContext, VehicleIdentity, revision: UInt64)
    /// 一意なarchived既存候補の確認待ちです。
    case archivedDuplicate(VehicleRegistrationWorkflowContext, VehicleIdentity, revision: UInt64)
    /// Repository transaction実行中です。
    case registering(operationID: UUID, revision: UInt64)
    /// commit結果不明のため同一Snapshotを再Queryする必要があります。
    case transactionResultUnknown(VehicleRegistrationWorkflowContext, operationID: UUID, revision: UInt64)
    /// archived車両へvalid Scanを追加済みで、明示復元待ちです。
    case archivedRestoreRequired(VehicleRegistrationWorkflowContext, VehicleIdentity, revision: UInt64)
    /// active登録済みです。binding pendingを別軸で保持します。
    case registered(VehicleIdentity, bindingPending: Bool, context: VehicleRegistrationWorkflowContext, revision: UInt64)
    /// IdentifierまたはRevisionが競合しています。
    case conflict(revision: UInt64)
    /// Hard Gateまたは依存回復待ちです。
    case blocked(revision: UInt64)
    /// 現attemptの終端失敗です。
    case failed(revision: UInt64)

    /// stale Action拒否に使うpresentation revisionです。
    var revision: UInt64 {
        switch self {
        case .idle(let revision), .conflict(let revision), .blocked(let revision), .failed(let revision):
            revision
        case .identifying(_, _, let revision),
             .registrationReady(_, let revision),
             .activeDuplicate(_, _, let revision),
             .archivedDuplicate(_, _, let revision),
             .registering(_, let revision),
             .transactionResultUnknown(_, _, let revision),
             .archivedRestoreRequired(_, _, let revision),
             .registered(_, _, _, let revision):
            revision
        }
    }
}
