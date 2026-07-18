import Foundation

/// 一接続のstate、Generation、Transport callbackを直列化するactorです。
actor ConnectionRuntime {
    private let role: CommunicationRole
    private let adapterReference: AdapterReference
    private let transport: any CommunicationTransport
    private let sink: any AcquisitionEventSink
    private var generationCounter: UInt64 = 0
    private(set) var state: ConnectionRuntimeState = .idle
    private(set) var staleEventCount: UInt64 = 0

    /// 固定roleとAdapter参照を一つのRuntimeへ注入します。
    /// - Parameters:
    ///   - role: Session中に変更しないPrimaryまたはSecondary。
    ///   - adapterReference: 不透明な物理Adapter参照。
    ///   - transport: Platform固有Transport境界。
    ///   - sink: 保存queueへの受渡し境界。
    init(role: CommunicationRole, adapterReference: AdapterReference, transport: any CommunicationTransport, sink: any AcquisitionEventSink) {
        self.role = role
        self.adapterReference = adapterReference
        self.transport = transport
        self.sink = sink
    }

    /// 新Generationで明示Endpointへ接続します。
    /// - Parameter endpoint: ユーザーが選択したTransport到達先。
    /// - Throws: Transportが利用不能または接続に失敗した場合。
    func connect(to endpoint: TransportEndpoint) async throws {
        let generation = nextGeneration()
        state = .connecting(generation)
        do {
            try await transport.open(endpoint: endpoint, generation: generation) { [weak self] event in
                guard let self else { return }
                Task { await self.receive(event, generation: generation) }
            }
        } catch {
            if isCurrent(generation) { state = .failed(.transportUnavailable) }
            throw error
        }
    }

    /// 現在Generationの取得開始状態へ進めます。
    /// - Throws: 接続準備前なら`transportUnavailable`。
    func beginAcquisition() throws {
        guard case let .ready(generation) = state else { throw CommunicationRuntimeError.transportUnavailable }
        state = .acquiring(generation)
    }

    /// 切断後、Adapter同一性と車両再識別が両方確定した場合だけ新Generationへ進みます。
    /// - Parameters:
    ///   - endpoint: 再探索で選ばれた到達先。
    ///   - adapterEvidence: 物理Adapter候補の同一性証拠。
    ///   - vehicleResult: Vehicle Identity境界による再識別結果。
    /// - Throws: 同一性不明、不一致、またはTransport失敗。
    func reconnect(to endpoint: TransportEndpoint, adapterEvidence: AdapterIdentityEvidence, vehicleResult: VehicleReidentificationResult) async throws {
        guard case let .sameAdapterConfirmed(reference) = adapterEvidence, reference == adapterReference else {
            state = .blocked(adapterEvidence == .unknown ? .adapterIdentityUnknown : .adapterAlreadyAssigned)
            throw adapterEvidence == .unknown ? CommunicationRuntimeError.adapterIdentityUnknown : CommunicationRuntimeError.adapterAlreadyAssigned
        }
        switch vehicleResult {
        case .sameVehicleConfirmed:
            try await connect(to: endpoint)
        case .differentVehicleConfirmed:
            state = .blocked(.vehicleIdentityMismatch)
            throw CommunicationRuntimeError.vehicleIdentityMismatch
        case .unavailable:
            state = .blocked(.vehicleReidentificationRequired)
            throw CommunicationRuntimeError.vehicleReidentificationRequired
        }
    }

    /// Generationを先に無効化し、callbackと自動再接続を止めます。
    func cancel() async {
        _ = nextGeneration()
        state = .idle
        await transport.close()
    }

    /// Transport callbackを現在Generationの場合だけ受理します。
    /// - Parameters:
    ///   - event: 低水準Transport Event。
    ///   - generation: callback生成時に捕捉した世代。
    private func receive(_ event: TransportEvent, generation: ConnectionGeneration) async {
        guard isCurrent(generation) else {
            staleEventCount += 1
            return
        }
        switch event {
        case .connected:
            state = .ready(generation)
        case let .received(bytes):
            do { try await sink.accept(.transportBytes(bytes, generation: generation)) }
            catch {
                state = .blocked(.storageUnavailable)
                await transport.close()
            }
        case .disconnected:
            state = .reconnectWait(generation)
            try? await sink.accept(.disconnected(generation: generation))
        case .failed:
            state = .failed(.transportUnavailable)
        }
    }

    /// process-local世代を進めて旧callbackを無効化します。
    /// - Returns: 新しいGeneration。
    private func nextGeneration() -> ConnectionGeneration {
        generationCounter += 1
        return ConnectionGeneration(value: generationCounter)
    }

    /// 状態が保持する現在Generationとの一致を確認します。
    /// - Parameter generation: callbackが捕捉した世代。
    /// - Returns: 現在世代なら`true`。
    private func isCurrent(_ generation: ConnectionGeneration) -> Bool {
        switch state {
        case let .connecting(current), let .ready(current), let .acquiring(current), let .reconnectWait(current): return current == generation
        case .idle, .blocked, .failed: return false
        }
    }
}
