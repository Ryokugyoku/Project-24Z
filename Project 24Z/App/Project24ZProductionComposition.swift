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
#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
        developmentDatabaseBrowserModel = DevelopmentDatabaseBrowserModel(readers: [
            UnavailableGRDBDevelopmentDatabaseReader(),
            SwiftDataItemDevelopmentDatabaseReader(container: modelContainer),
        ])
#endif

        let runtime = UnavailablePIDVehicleRuntime()
        let workflow = VehicleRegistrationWorkflow(
            vehicleRepository: UnavailableVehicleIdentityRepository(),
            bindingRepository: UnavailableSessionVehicleBindingRepository()
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
        vehicleRegistrationServices = VehicleRegistrationProductionServices(
            workflow: workflow,
            connectionRuntime: connectionRuntime,
            supportDiscoveryCoordinator: PIDSupportDiscoveryCoordinator(runtime: runtime),
            adaptivePollingCoordinator: AdaptivePollingCoordinator(runtime: runtime),
            blockedReason: "認証済みuser scopeとPID-HG-02／03／04／05／06／07／10／11が未達です。"
        )
        vehicleRegistrationModel = VehicleRegistrationModel(
            productionServices: vehicleRegistrationServices
        )

#if os(macOS)
        let unavailablePlatform = LocalDeviceScope.Platform.macOS
#else
        let unavailablePlatform = LocalDeviceScope.Platform.iOS
#endif
        let unavailableScope = LocalDeviceScope(
            userScopeID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            localDeviceScopeID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            platform: unavailablePlatform
        )
        let adapterRepository = UnavailableDefaultAdapterRepository()
        connectionSettingsModel = ConnectionSettingsModel(
            scope: unavailableScope,
            repository: adapterRepository,
            discovery: UnavailableConnectionEndpointDiscovery(),
            availabilityMessage: "対応Adapter、firmware、Transport、認証済み保存ScopeのHard Gateが未達のため、Production接続は利用できません。"
        )
        let startCoordinator = AcquisitionStartCoordinator(
            scope: unavailableScope,
            repository: adapterRepository,
            preflight: UnavailableAcquisitionStartPreflight(),
            primaryPreparer: UnavailableAdapterConnectionPreparer(),
            secondaryPreparer: UnavailableAdapterConnectionPreparer(),
            sessionStarter: UnavailableAcquisitionSessionStarter(),
            activator: UnavailablePreparedAcquisitionActivator()
        )
        dashboardModel = DashboardModel(
            repository: adapterRepository,
            scope: unavailableScope,
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
