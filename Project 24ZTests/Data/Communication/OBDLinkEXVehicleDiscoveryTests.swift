#if os(macOS)
import Foundation
import Testing
@testable import Project_24Z

/// OBDLink EX実車pilotのexact順序、VIN、PID Decode、安全停止を検証します。
struct OBDLinkEXVehicleDiscoveryTests {
    /// 固定transcriptからVINと4 PID値を復元し、最後にcloseすることを検証します。
    @Test
    func approvedReadOnlyTranscriptProducesVehicleSnapshot() async throws {
        let transport = VehicleTranscriptTransport()
        let discovery = OBDLinkEXVehicleDiscovery(
            endpointLocator: FixedUSBSerialEndpointLocator(
                endpoints: [TransportEndpoint(identifier: "/dev/cu.fixture", kind: .usbSerial)]
            ),
            transport: transport
        )

        let snapshot = try await discovery.discoverVehicle()

        #expect(snapshot.vin == "1HGCM82633A004352")
        #expect(snapshot.diagnosticProtocol == "ISO 15765-4 (CAN 11/500)")
        #expect(snapshot.successfulPIDValues.map(\.parameter) == [0x04, 0x05, 0x0C, 0x0D])
        #expect(snapshot.successfulPIDValues.map(\.value) == [127.0 * 100.0 / 255.0, 60, 1000, 50])
        #expect(await transport.recordedCloseCount() == 1)
        #expect(await transport.recordedWrites().map { String(decoding: $0, as: UTF8.self) } == [
            "??\r", "ATZ\r", "STDI\r", "STI\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATSP0\r",
            "0902\r", "ATDP\r", "0104\r", "0105\r", "010C\r", "010D\r",
        ])
    }

    /// 不正VINを登録可能Snapshotへ昇格せずcloseすることを検証します。
    @Test
    func malformedVINClosesWithoutPollingPIDs() async {
        let transport = VehicleTranscriptTransport(vinResponse: Data("49 02 01 31 32 33\r>".utf8))
        let discovery = OBDLinkEXVehicleDiscovery(
            endpointLocator: FixedUSBSerialEndpointLocator(
                endpoints: [TransportEndpoint(identifier: "/dev/cu.fixture", kind: .usbSerial)]
            ),
            transport: transport
        )

        await #expect(throws: CommunicationRuntimeError.malformedResponse) {
            try await discovery.discoverVehicle()
        }
        #expect(await transport.recordedWrites().last == Data("0902\r".utf8))
        #expect(await transport.recordedCloseCount() == 1)
    }

    /// write／reset／Raw CAN用途がpilot allowlistへ混入しないことを検証します。
    @Test
    func vehicleAllowlistRejectsUnapprovedRequests() throws {
        let encoder = OBDLinkEXVehicleCommandAllowlist.version1
        #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try encoder.encode(.rawMonitorStart)
        }
        #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try encoder.encode(.standardOBD(.init(purpose: .currentData(parameter: 0x10))))
        }
    }
}
#endif
