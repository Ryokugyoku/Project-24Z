import Foundation
import SwiftData

/// Production用のApplication、Data、Runtime依存を一度だけ組み立てます。
@MainActor
final class Project24ZProductionComposition {
    /// SwiftDataをSystem of Recordとする既存機能用コンテナです。
    let modelContainer: ModelContainer

    /// Platformへ渡す唯一の車両登録Application Modelです。
    let vehicleRegistrationModel: VehicleRegistrationModel

    /// 接続せず既定候補を管理するApplication Modelです。
    let connectionSettingsModel: ConnectionSettingsModel

    /// ログ収集開始導線を管理するApplication Modelです。
    let dashboardModel: DashboardModel

    /// HOMEへ最後の実車PID Snapshotを公開するApplication Modelです。
    let telemetryModel: VehicleTelemetryModel

#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
    /// 専用flag構成だけで生成するread-only Development Database Browserです。
    let developmentDatabaseBrowserModel: DevelopmentDatabaseBrowserModel
#endif

    /// Production Workflowを生存期間中保持します。
    private let vehicleRegistrationServices: VehicleRegistrationProductionServices

    /// Production依存を構成します。
    ///
    /// 認証済みuser scope、識別command一次根拠、Adapter transcript、Crypto／Digestが未接続のため、
    /// Vehicle Identity Storeを架空scopeで開かず、非破壊停止Adapterへ接続します。
    /// - Throws: SwiftDataコンテナを生成できない場合のエラー。
    init() throws {
        modelContainer = try SwiftDataContainerFactory.makeContainer()
        telemetryModel = VehicleTelemetryModel()
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
        developmentDatabaseBrowserModel = DevelopmentDatabaseBrowserModel(readers: [
            UnavailableGRDBDevelopmentDatabaseReader(),
            SwiftDataItemDevelopmentDatabaseReader(container: modelContainer),
        ])
#endif

        let runtime = UnavailablePIDVehicleRuntime()
#if os(macOS)
        let platform = LocalDeviceScope.Platform.macOS
#else
        let platform = LocalDeviceScope.Platform.iOS
#endif
        let localScope = LocalInstallationScopeProvider().scope(platform: platform)
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseDirectory = applicationSupport.appendingPathComponent("Project24Z", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        let storeResult = GRDBVehicleIdentityStore.open(
            at: databaseDirectory.appendingPathComponent("vehicle-identity.sqlite"),
            userScopeID: localScope.userScopeID,
            activeDigestKeyVersion: 1
        )
        let vehicleRepository: any VehicleIdentityRepository
        let bindingRepository: any SessionVehicleBindingRepository
        let acquisitionRepository: (any AcquisitionRepository)?
        let sessionRepository: (any UnassignedSessionRepository)?
        let acquisitionStopRepository: (any AcquisitionSessionStopPersisting)?
        let storeUnavailableReason: String?
        switch storeResult {
        case .available(let store):
            vehicleRepository = store.repository
            bindingRepository = store.acquisitionRepository
            acquisitionRepository = store.acquisitionRepository
            sessionRepository = store.acquisitionRepository
            acquisitionStopRepository = store.acquisitionRepository
            storeUnavailableReason = nil
        case .unavailable(let unavailable):
            vehicleRepository = UnavailableVehicleIdentityRepository()
            bindingRepository = UnavailableSessionVehicleBindingRepository()
            acquisitionRepository = nil
            sessionRepository = nil
            acquisitionStopRepository = nil
            storeUnavailableReason = "GRDB Storeを安全に開けませんでした（\(unavailable.reason)）。"
        }
        let workflow = VehicleRegistrationWorkflow(
            vehicleRepository: vehicleRepository,
            bindingRepository: bindingRepository,
            sessionRepository: sessionRepository
        )
#if os(iOS)
        let transport: any CommunicationTransport = IOSUnavailableWirelessTransport()
#elseif os(macOS)
        let transport: any CommunicationTransport = MacOSUnavailableTransport()
#else
        let transport: any CommunicationTransport = UnsupportedPlatformTransport()
#endif
        let connectionRuntime = ConnectionRuntime(
            role: .primaryOBD,
            adapterReference: AdapterReference(opaqueID: "production-unavailable-adapter"),
            transport: transport,
            sink: UnavailableAcquisitionEventSink()
        )
#if DEBUG && os(macOS)
        let adapterIdentityProbe: (any AdapterIdentityProbing)? = ELMAdapterIdentityProbe(
            endpointLocator: MacOSOBDLinkEXEndpointLocator(),
            transport: MacOSUSBSerialTransport(),
            encoder: OBDLinkEXIdentityCommandAllowlist.version1
        )
#else
        let adapterIdentityProbe: (any AdapterIdentityProbing)? = nil
#endif
#if os(macOS)
        let vehicleDiscoverer: (any OBDVehicleDiscovering)? = storeUnavailableReason == nil
            ? OBDLinkEXVehicleDiscovery(
                endpointLocator: MacOSOBDLinkEXEndpointLocator(),
                transport: MacOSUSBSerialTransport()
            )
            : nil
        let sensitiveValueProtector: (any VehicleSensitiveValueProtecting)? = storeUnavailableReason == nil
            ? KeychainVehicleSensitiveValueProtector()
            : nil
#else
        let vehicleDiscoverer: (any OBDVehicleDiscovering)? = nil
        let sensitiveValueProtector: (any VehicleSensitiveValueProtecting)? = nil
#endif
        vehicleRegistrationServices = VehicleRegistrationProductionServices(
            workflow: workflow,
            connectionRuntime: connectionRuntime,
            supportDiscoveryCoordinator: PIDSupportDiscoveryCoordinator(runtime: runtime),
            adaptivePollingCoordinator: AdaptivePollingCoordinator(runtime: runtime),
            adapterIdentityProbe: adapterIdentityProbe,
            vehicleDiscoverer: vehicleDiscoverer,
            sensitiveValueProtector: sensitiveValueProtector,
            acquisitionRepository: acquisitionRepository,
            acquisitionStopRepository: acquisitionStopRepository,
            localScope: acquisitionRepository == nil ? nil : localScope,
            telemetryModel: telemetryModel,
            blockedReason: storeUnavailableReason
                ?? "このPlatformにはOBDLink EX USB serial Transportがありません。macOS TestFlightで確認してください。"
        )
        vehicleRegistrationModel = VehicleRegistrationModel(
            productionServices: vehicleRegistrationServices
        )

        let adapterRepository = UnavailableDefaultAdapterRepository()
        connectionSettingsModel = ConnectionSettingsModel(
            scope: localScope,
            repository: adapterRepository,
            discovery: UnavailableConnectionEndpointDiscovery(),
            availabilityMessage: "対応Adapter、firmware、Transport、認証済み保存ScopeのHard Gateが未達のため、Production接続は利用できません。"
        )
        let startCoordinator = AcquisitionStartCoordinator(
            scope: localScope,
            repository: adapterRepository,
            preflight: UnavailableAcquisitionStartPreflight(),
            primaryPreparer: UnavailableAdapterConnectionPreparer(),
            secondaryPreparer: UnavailableAdapterConnectionPreparer(),
            sessionStarter: UnavailableAcquisitionSessionStarter(),
            activator: UnavailablePreparedAcquisitionActivator()
        )
        dashboardModel = DashboardModel(
            repository: adapterRepository,
            scope: localScope,
            coordinator: startCoordinator,
            stopCoordinator: nil
        )
    }
}

#if !os(iOS) && !os(macOS)
import Foundation

/// 対象外PlatformでProduction通信を明示的に拒否します。
private struct UnsupportedPlatformTransport: CommunicationTransport {
    /// Endpointを開かず拒否します。
    /// - Parameters:
    ///   - endpoint: 開かないEndpoint。
    ///   - generation: 使用しないGeneration。
    ///   - eventHandler: 呼び出さないcallback。
    /// - Throws: 常に`transportUnavailable`。
    func open(
        endpoint: TransportEndpoint,
        generation: ConnectionGeneration,
        eventHandler: @escaping @Sendable (TransportEvent) -> Void
    ) async throws {
        throw CommunicationRuntimeError.transportUnavailable
    }

    /// bytesを書き込まず拒否します。
    /// - Parameters:
    ///   - bytes: 書き込まないbytes。
    ///   - generation: 使用しないGeneration。
    /// - Throws: 常に`transportUnavailable`。
    func write(_ bytes: Data, generation: ConnectionGeneration) async throws {
        throw CommunicationRuntimeError.transportUnavailable
    }

    /// 解放対象がないため何もしません。
    func close() async {}
}
#endif
