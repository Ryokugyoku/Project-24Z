import Foundation
import Testing
@testable import Project_24Z

/// Raw CANのreceive-only、safety gate、allowlist境界を検証します。
struct RawCANReceiveChannelTests {
    /// safety未検証ならmonitor開始commandを一切writeしません。
    @Test
    func unverifiedSafetyBlocksBeforeMonitorCommand() async {
        let transport = FakeCommunicationTransport()
        let encoder = VersionedELMCommandAllowlist(version: 1, adapterModel: "fixture", firmwareVersion: "fixture", mode: "monitor", entries: [.init(request: .rawMonitorStart, bytes: Data([0xAA]))])
        let channel = AllowlistedRawCANReceiveChannel(transport: transport, encoder: encoder, generation: .init(value: 1))

        await #expect(throws: CommunicationRuntimeError.rawReceiveSafetyUnverified) {
            try await channel.startListening(configuration: .init(safetyEvidence: .unknown))
        }
        #expect(await transport.writeCount() == 0)
    }

    /// allowlist外のmonitor開始はsafety証拠があってもwriteしません。
    @Test
    func monitorStartOutsideAllowlistIsRejected() async {
        let transport = FakeCommunicationTransport()
        let channel = AllowlistedRawCANReceiveChannel(transport: transport, encoder: UnavailableELMCommandEncoder(), generation: .init(value: 1))

        await #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try await channel.startListening(configuration: .init(safetyEvidence: .adapterModeVerified))
        }
        #expect(await transport.writeCount() == 0)
    }

    /// 公開channelは注入された受信Eventだけを返し、開始／停止以外のbus送信操作を持ちません。
    @Test
    func receiveOnlyChannelYieldsRawWithoutMutation() async throws {
        let transport = FakeCommunicationTransport()
        let encoder = VersionedELMCommandAllowlist(version: 3, adapterModel: "fixture", firmwareVersion: "fixture", mode: "monitor", entries: [.init(request: .rawMonitorStart, bytes: Data([0x10])), .init(request: .rawMonitorStop, bytes: Data([0x11]))])
        let channel = AllowlistedRawCANReceiveChannel(transport: transport, encoder: encoder, generation: .init(value: 1))
        try await channel.startListening(configuration: .init(safetyEvidence: .adapterModeVerified))
        let event = RawCANEvent(identifier: 0x7E8, identifierFormat: .standard11Bit, dlc: 8, payload: Data([1,2,3,4,5,6,7,8]), rawBytes: Data([0xDE,0xAD]), parseState: .parsed, generation: .init(value: 1))
        await channel.ingest(event)

        #expect(await channel.nextEvent() == event)
        await channel.stopListening()
        #expect(await transport.writeCount() == 2)
    }
}
