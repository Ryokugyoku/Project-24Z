/// 一意に照合された既存車両候補を表します。
struct VehicleRegistrationDuplicateCandidate: Equatable, Sendable {
    /// 候補車両のライフサイクル状態です。
    enum Lifecycle: Equatable, Sendable {
        /// 現在利用中の車両です。
        case active

        /// 明示復元が必要なアーカイブ済み車両です。
        case archived
    }

    /// 候補のライフサイクル状態です。
    let lifecycle: Lifecycle

    /// stale候補を拒否するためのrevisionです。
    let lifecycleRevision: Int

    /// 候補の安全な表示値です。
    let display: VehicleRegistrationDisplayValues

    /// 既存車両候補を生成します。
    /// - Parameters:
    ///   - lifecycle: 候補のライフサイクル状態。
    ///   - lifecycleRevision: 候補の現在revision。
    ///   - display: 候補の安全な表示値。
    init(
        lifecycle: Lifecycle,
        lifecycleRevision: Int,
        display: VehicleRegistrationDisplayValues
    ) {
        self.lifecycle = lifecycle
        self.lifecycleRevision = lifecycleRevision
        self.display = display
    }
}
