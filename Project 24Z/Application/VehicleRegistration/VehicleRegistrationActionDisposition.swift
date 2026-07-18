/// 未実装または無効な車両登録Actionの拒否結果です。
enum VehicleRegistrationActionDisposition: Equatable, Sendable {
    /// 表示更新後の古いActionであるため拒否しました。
    case rejectedStalePresentation

    /// 同じActionの重複通知であるため拒否しました。
    case rejectedDuplicateAction

    /// 現在Stateでは公開されないActionであるため拒否しました。
    case rejectedInvalidState

    /// archived候補のlifecycle revisionが古いため拒否しました。
    case rejectedStaleLifecycleRevision

    /// Production依存が未実装であるため拒否しました。
    case rejectedUnavailable
}
