/// ローカル同期台帳が安全に処理を拒否した理由です。
enum SyncPersistenceError: Error, Equatable {
    /// 入力がVersion、Digest、状態契約を満たしません。
    case invalidRequest
    /// 現在状態または既存行と競合しました。
    case conflict
    /// ConflictまたはQuarantineにより前進できません。
    case blocked
    /// DB、容量、整合性の問題により非破壊で停止しました。
    case unavailable
}
