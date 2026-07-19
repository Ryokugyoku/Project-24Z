import Foundation
import Testing
@testable import Project_24Z

/// Generation、再接続、取消し、保存失敗のRuntime境界を検証します。
struct ConnectionRuntimeTests {
    /// reconnect後に旧Generation callbackを保存しません。
    @Test
    func staleCallbackIsRejectedAfterReconnect() async throws {
        let transport = FakeCommunicationTransport()
        let sink = FakeAcquisitionEventSink()
        let adapter = AdapterReference(opaqueID: "adapter-a")
        let runtime = ConnectionRuntime(role: .primaryOBD, adapterReference: adapter, transport: transport, sink: sink)
        let endpoint = TransportEndpoint(identifier: "endpoint", kind: .bluetoothLE)

        try await runtime.connect(to: endpoint)
        await transport.emit(.connected, generation: .init(value: 1))
        await transport.emit(.disconnected, generation: .init(value: 1))
        try await eventually { await runtime.state == .reconnectWait(.init(value: 1)) }
        try await runtime.reconnect(to: endpoint, adapterEvidence: .sameAdapterConfirmed(adapter), vehicleResult: .sameVehicleConfirmed)
        await transport.emit(.connected, generation: .init(value: 2))
        await transport.emit(.received(Data([0xAA])), generation: .init(value: 1))
        await transport.emit(.received(Data([0xBB])), generation: .init(value: 2))

        try await eventually {
            let eventCount = await sink.eventCount()
            let staleCount = await runtime.staleEventCount
            return eventCount == 2 && staleCount == 1
        }
        #expect(await runtime.staleEventCount == 1)
        #expect(await sink.lastEvent() == .transportBytes(Data([0xBB]), generation: .init(value: 2)))
    }

    /// 車両再識別不能では新しい接続を開始しません。
    @Test
    func reconnectRequiresVehicleReidentification() async throws {
        let transport = FakeCommunicationTransport()
        let adapter = AdapterReference(opaqueID: "adapter-a")
        let runtime = ConnectionRuntime(role: .primaryOBD, adapterReference: adapter, transport: transport, sink: FakeAcquisitionEventSink())
        let endpoint = TransportEndpoint(identifier: "endpoint", kind: .usbSerial)
        try await runtime.connect(to: endpoint)
        await transport.emit(.disconnected, generation: .init(value: 1))
        try await eventually { await runtime.state == .reconnectWait(.init(value: 1)) }

        await #expect(throws: CommunicationRuntimeError.vehicleReidentificationRequired) {
            try await runtime.reconnect(to: endpoint, adapterEvidence: .sameAdapterConfirmed(adapter), vehicleResult: .unavailable)
        }
        #expect(await runtime.state == .blocked(.vehicleReidentificationRequired))
    }

    /// Sink失敗時に受信を保存済み扱いせず非破壊停止します。
    @Test
    func storageAcceptanceFailureBlocksRuntime() async throws {
        let transport = FakeCommunicationTransport()
        let sink = FakeAcquisitionEventSink()
        await sink.setFailure(true)
        let runtime = ConnectionRuntime(role: .secondaryRawCAN, adapterReference: .init(opaqueID: "adapter-b"), transport: transport, sink: sink)
        try await runtime.connect(to: .init(identifier: "endpoint", kind: .tcp))
        await transport.emit(.connected, generation: .init(value: 1))
        await transport.emit(.received(Data([0x01])), generation: .init(value: 1))

        try await eventually { await runtime.state == .blocked(.storageUnavailable) }
        #expect(await sink.eventCount() == 0)
        #expect(await transport.closeCount == 1)
    }

    /// user取消し後のcallbackを無視し再接続しません。
    @Test
    func cancellationInvalidatesGeneration() async throws {
        let transport = FakeCommunicationTransport()
        let sink = FakeAcquisitionEventSink()
        let runtime = ConnectionRuntime(role: .primaryOBD, adapterReference: .init(opaqueID: "adapter-a"), transport: transport, sink: sink)
        try await runtime.connect(to: .init(identifier: "endpoint", kind: .bluetoothClassic))
        await runtime.cancel()
        await transport.emit(.received(Data([0xCC])), generation: .init(value: 1))
        await transport.emit(.disconnected, generation: .init(value: 1))
        try await Task.sleep(for: .milliseconds(5))

        #expect(await runtime.state == .idle)
        #expect(await runtime.staleEventCount == 2)
        #expect(await sink.eventCount() == 0)
    }

    /// 非同期callbackの反映を短い上限内で待ちます。
    /// - Parameter predicate: 成立条件。
    /// - Throws: 上限内に成立しない場合。
    private func eventually(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            await Task.yield()
        }
        throw CommunicationRuntimeError.commandTimedOut
    }
}
