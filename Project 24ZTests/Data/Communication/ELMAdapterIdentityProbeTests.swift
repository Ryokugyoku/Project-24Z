import Foundation
import Testing
@testable import Project_24Z

/// OBDLink EX Adapter単体Probeのexact allowlist、順序、停止境界を検証します。
struct ELMAdapterIdentityProbeTests {
    /// Runbookの4 commandを各一回、固定順序で送り、成功後にcloseすることを検証します。
    @Test
    func approvedTranscriptIsExecutedExactlyOnceInOrder() async throws {
        let transport = IdentityTranscriptTransport()
        let probe = ELMAdapterIdentityProbe(
            endpointLocator: FixedUSBSerialEndpointLocator(
                endpoints: [TransportEndpoint(identifier: "/dev/cu.fixture", kind: .usbSerial)]
            ),
            transport: transport,
            encoder: OBDLinkEXIdentityCommandAllowlist.version1
        )

        let identity = try await probe.verifyApprovedAdapter()

        #expect(identity.displayName == "OBDLink EX (EX101)")
        #expect(identity.hardwareVersion == "OBDLink EX r2.7.1")
        #expect(identity.firmwareVersion == "STN2232 v5.10.3")
        #expect(await transport.recordedWrites() == [
            Data("??\r".utf8),
            Data("ATZ\r".utf8),
            Data("STDI\r".utf8),
            Data("STI\r".utf8),
        ])
        #expect(await transport.recordedCloseCount() == 1)
    }

    /// Endpointが0件ならopenもwriteもせず停止することを検証します。
    @Test
    func zeroEndpointsAreRejectedWithoutSending() async {
        let transport = IdentityTranscriptTransport()
        let probe = ELMAdapterIdentityProbe(
            endpointLocator: FixedUSBSerialEndpointLocator(endpoints: []),
            transport: transport,
            encoder: OBDLinkEXIdentityCommandAllowlist.version1
        )

        await #expect(throws: CommunicationRuntimeError.transportUnavailable) {
            try await probe.verifyApprovedAdapter()
        }
        #expect(await transport.recordedWrites().isEmpty)
        #expect(await transport.recordedCloseCount() == 0)
    }

    /// 想定外identity応答を成功扱いせず、追加送信を止めてcloseすることを検証します。
    @Test
    func unexpectedIdentityResponseClosesTransport() async {
        let transport = IdentityTranscriptTransport(
            firmwareResponse: Data("STI\rUNKNOWN\r>".utf8)
        )
        let probe = ELMAdapterIdentityProbe(
            endpointLocator: FixedUSBSerialEndpointLocator(
                endpoints: [TransportEndpoint(identifier: "/dev/cu.fixture", kind: .usbSerial)]
            ),
            transport: transport,
            encoder: OBDLinkEXIdentityCommandAllowlist.version1
        )

        await #expect(throws: CommunicationRuntimeError.adapterIdentityUnknown) {
            try await probe.verifyApprovedAdapter()
        }
        #expect(await transport.recordedWrites().count == 4)
        #expect(await transport.recordedCloseCount() == 1)
    }

    /// allowlistが車両Request、Raw CAN、任意未証明用途を拒否することを検証します。
    @Test
    func identityAllowlistRejectsVehicleAndRawCANRequests() throws {
        let encoder = OBDLinkEXIdentityCommandAllowlist.version1

        #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try encoder.encode(.rawMonitorStart)
        }
        #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try encoder.encode(
                .standardOBD(OBDDiagnosticRequest(purpose: .currentData(parameter: 0)))
            )
        }
    }
}
