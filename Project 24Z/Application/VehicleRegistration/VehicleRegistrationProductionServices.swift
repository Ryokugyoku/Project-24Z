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

    /// Development macOSでだけ利用できるAdapter単体identity Probeです。
    let adapterIdentityProbe: (any AdapterIdentityProbing)?

    /// macOS実車pilotでread-only識別とPID probeを実行する境界です。
    let vehicleDiscoverer: (any OBDVehicleDiscovering)?

    /// VINとRaw応答をRepository投入前に保護する境界です。
    let sensitiveValueProtector: (any VehicleSensitiveValueProtecting)?

    /// 識別用Acquisition SessionをGRDBへ保存する境界です。
    let acquisitionRepository: (any AcquisitionRepository)?

    /// 識別Sessionを正本順序で停止するGRDB境界です。
    let acquisitionStopRepository: (any AcquisitionSessionStopPersisting)?

    /// 現在のローカルpilot scopeです。
    let localScope: LocalDeviceScope?

    /// HOMEへ成功PID Snapshotを通知するModelです。
    let telemetryModel: VehicleTelemetryModel

    /// Hard Gate未達時に画面へ公開できる安定理由です。
    let blockedReason: String

    /// Production用Applicationサービスを構成します。
    /// - Parameters:
    ///   - workflow: Data Repositoryへ接続済みの登録Workflow。
    ///   - connectionRuntime: Platform Transportへ接続済みのConnection Runtime。
    ///   - supportDiscoveryCoordinator: Runtimeへ接続済みの対応探索Coordinator。
    ///   - adaptivePollingCoordinator: Runtimeへ接続済みのPolling Coordinator。
    ///   - adapterIdentityProbe: 車両busへ触れない承認済みAdapter単体Probe。Productionではnil。
    ///   - vehicleDiscoverer: macOS read-only実車識別境界。未対応Platformではnil。
    ///   - sensitiveValueProtector: VINとRaw応答の暗号・照合Digest境界。
    ///   - acquisitionRepository: 識別Sessionを作成するGRDB境界。
    ///   - acquisitionStopRepository: 識別Sessionを停止するGRDB境界。
    ///   - localScope: ローカルpilotのUser／Device scope。
    ///   - telemetryModel: HOMEへ成功PID Snapshotを公開するModel。
    ///   - blockedReason: Production機能を開始できない安定理由。
    init(
        workflow: VehicleRegistrationWorkflow,
        connectionRuntime: ConnectionRuntime,
        supportDiscoveryCoordinator: PIDSupportDiscoveryCoordinator,
        adaptivePollingCoordinator: AdaptivePollingCoordinator,
        adapterIdentityProbe: (any AdapterIdentityProbing)? = nil,
        vehicleDiscoverer: (any OBDVehicleDiscovering)? = nil,
        sensitiveValueProtector: (any VehicleSensitiveValueProtecting)? = nil,
        acquisitionRepository: (any AcquisitionRepository)? = nil,
        acquisitionStopRepository: (any AcquisitionSessionStopPersisting)? = nil,
        localScope: LocalDeviceScope? = nil,
        telemetryModel: VehicleTelemetryModel,
        blockedReason: String
    ) {
        self.workflow = workflow
        self.connectionRuntime = connectionRuntime
        self.supportDiscoveryCoordinator = supportDiscoveryCoordinator
        self.adaptivePollingCoordinator = adaptivePollingCoordinator
        self.adapterIdentityProbe = adapterIdentityProbe
        self.vehicleDiscoverer = vehicleDiscoverer
        self.sensitiveValueProtector = sensitiveValueProtector
        self.acquisitionRepository = acquisitionRepository
        self.acquisitionStopRepository = acquisitionStopRepository
        self.localScope = localScope
        self.telemetryModel = telemetryModel
        self.blockedReason = blockedReason
    }
}
