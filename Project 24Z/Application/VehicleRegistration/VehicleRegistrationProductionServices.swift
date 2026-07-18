/// Production Compositionから車両登録画面へ渡すApplicationサービス群です。
@MainActor
final class VehicleRegistrationProductionServices {
    /// 識別、登録、復元、Session所属を調停するWorkflowです。
    let workflow: VehicleRegistrationWorkflow

    /// Platform Transport callbackと接続Generationを直列化するRuntimeです。
    let connectionRuntime: ConnectionRuntime

    /// 型付きPID対応探索を調停するCoordinatorです。
    let supportDiscoveryCoordinator: PIDSupportDiscoveryCoordinator

    /// 型付きPID pollingを調停するCoordinatorです。
    let adaptivePollingCoordinator: AdaptivePollingCoordinator

    /// Hard Gate未達時に画面へ公開できる安定理由です。
    let blockedReason: String

    /// Production用Applicationサービスを構成します。
    /// - Parameters:
    ///   - workflow: Data Repositoryへ接続済みの登録Workflow。
    ///   - connectionRuntime: Platform Transportへ接続済みのConnection Runtime。
    ///   - supportDiscoveryCoordinator: Runtimeへ接続済みの対応探索Coordinator。
    ///   - adaptivePollingCoordinator: Runtimeへ接続済みのPolling Coordinator。
    ///   - blockedReason: Production機能を開始できない安定理由。
    init(
        workflow: VehicleRegistrationWorkflow,
        connectionRuntime: ConnectionRuntime,
        supportDiscoveryCoordinator: PIDSupportDiscoveryCoordinator,
        adaptivePollingCoordinator: AdaptivePollingCoordinator,
        blockedReason: String
    ) {
        self.workflow = workflow
        self.connectionRuntime = connectionRuntime
        self.supportDiscoveryCoordinator = supportDiscoveryCoordinator
        self.adaptivePollingCoordinator = adaptivePollingCoordinator
        self.blockedReason = blockedReason
    }
}
