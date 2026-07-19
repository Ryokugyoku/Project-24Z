import Foundation
import Testing
@testable import Project_24Z

/// 設定画面が探索・候補保存だけを行う状態遷移を検証します。
@MainActor
struct ConnectionSettingsModelTests {
    /// Primary／Secondaryが端末別・役割別に分離されることを検証します。
    @Test
    func savesCandidatesByRoleAndDevice() async throws {
        let repository = InMemoryDefaultAdapterRepository()
        let discovery = FakeConnectionEndpointDiscovery()
        let phoneScope = scope(device: UUID(), platform: .iOS)
        let macScope = scope(device: UUID(), platform: .macOS)
        let primary = try candidate(byte: 1, name: "Primary")
        let secondary = try candidate(byte: 2, name: "Secondary")
        discovery.candidates = [primary, secondary]
        let model = ConnectionSettingsModel(scope: phoneScope, repository: repository, discovery: discovery, now: { Date(timeIntervalSince1970: 1) })

        await model.perform(.selectCandidate(primary, role: .primaryOBD))
        await model.perform(.selectCandidate(secondary, role: .secondaryRawCAN))

        #expect(model.state.primary.candidate?.endpoint == primary)
        #expect(model.state.secondary.candidate?.endpoint == secondary)
        #expect(try repository.activeCandidates(in: macScope).isEmpty)
    }

    /// 同一Endpointを両役割へ設定せず直前のPrimaryを維持します。
    @Test
    func rejectsSameEndpointAcrossRoles() async throws {
        let repository = InMemoryDefaultAdapterRepository()
        let model = ConnectionSettingsModel(scope: scope(device: UUID(), platform: .iOS), repository: repository, discovery: FakeConnectionEndpointDiscovery())
        let value = try candidate(byte: 3, name: "Only")
        await model.perform(.selectCandidate(value, role: .primaryOBD))
        await model.perform(.selectCandidate(value, role: .secondaryRawCAN))

        #expect(model.state.primary.candidate?.endpoint == value)
        #expect(model.state.secondary.candidate == nil)
        #expect(model.state.secondary.failureMessage != nil)
    }

    /// Bluetooth権限は明示的な選択開始まで要求境界を呼ばないことを検証します。
    @Test
    func discoveryStartsOnlyAfterExplicitActionAndCancels() async throws {
        let discovery = FakeConnectionEndpointDiscovery()
        discovery.candidates = [try candidate(byte: 4, name: "BLE")]
        let model = ConnectionSettingsModel(scope: scope(device: UUID(), platform: .iOS), repository: InMemoryDefaultAdapterRepository(), discovery: discovery)
        #expect(discovery.discoveryCount == 0)

        await model.perform(.beginDiscovery(role: .primaryOBD, transportKind: .bluetoothLE))
        #expect(discovery.discoveryCount == 1)
        #expect(model.state.discoveredCandidates.count == 1)

        await model.perform(.cancelDiscovery)
        #expect(discovery.cancellationCount == 1)
        #expect(model.state.selectingRole == nil)
    }

    /// 固定Digest候補を作ります。
    /// - Parameters:
    ///   - byte: Digest byte。
    ///   - name: 表示名。
    /// - Returns: 候補fixture。
    private func candidate(byte: UInt8, name: String) throws -> ConnectionEndpointCandidate {
        try .init(endpointDigest: Data(repeating: byte, count: 32), displayName: name, transportKind: .bluetoothLE)
    }

    /// テスト用端末scopeを作ります。
    /// - Parameters:
    ///   - device: 端末ID。
    ///   - platform: Platform。
    /// - Returns: scope fixture。
    private func scope(device: UUID, platform: LocalDeviceScope.Platform) -> LocalDeviceScope {
        .init(userScopeID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, localDeviceScopeID: device, platform: platform)
    }
}
