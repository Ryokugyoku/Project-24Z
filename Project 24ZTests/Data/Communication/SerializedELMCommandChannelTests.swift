import Foundation
import Testing
@testable import Project_24Z

/// ELM commandのFIFO直列化、timeout、cancel、allowlist拒否を検証します。
struct SerializedELMCommandChannelTests {
    /// 二つのcommandは前commandのprompt終端後にだけ順にwriteされます。
    @Test
    func commandsAreSerializedAndCorrelated() async throws {
        let transport = FakeCommunicationTransport()
        let request1 = ELMCommandRequest.standardOBD(.init(purpose: .currentData(parameter: 12)))
        let request2 = ELMCommandRequest.standardOBD(.init(purpose: .currentData(parameter: 13)))
        let encoder = VersionedELMCommandAllowlist(version: 7, adapterModel: "fixture", firmwareVersion: "fixture", mode: "obd", entries: [.init(request: request1, bytes: Data("ONE\r".utf8)), .init(request: request2, bytes: Data("TWO\r".utf8))])
        let channel = SerializedELMCommandChannel(transport: transport, encoder: encoder)
        let first = Task { try await channel.execute(request: request1, generation: .init(value: 1), timeout: .seconds(1)) }
        try await eventually { await transport.writeCount() == 1 }
        let second = Task { try await channel.execute(request: request2, generation: .init(value: 1), timeout: .seconds(1)) }
        await channel.receive(Data("41 0C\r>".utf8), generation: .init(value: 1))
        try await eventually { await transport.writeCount() == 2 }
        await channel.receive(Data("41 0D\r>".utf8), generation: .init(value: 1))
        let results = try await (first.value, second.value)

        #expect(results.0.commandSequence == 1)
        #expect(results.1.commandSequence == 2)
        #expect(results.0.rawBytes == Data("41 0C\r>".utf8))
        #expect(await transport.writtenBytes(at: 0) == Data("ONE\r".utf8))
        #expect(await transport.writtenBytes(at: 1) == Data("TWO\r".utf8))
    }

    /// timeout時のpartial Rawを次commandへ流用しません。
    @Test
    func timeoutPreservesPartialResponse() async throws {
        let transport = FakeCommunicationTransport()
        let request = ELMCommandRequest.standardOBD(.init(purpose: .vehicleIdentification(parameter: 2)))
        let encoder = VersionedELMCommandAllowlist(version: 1, adapterModel: "fixture", firmwareVersion: "fixture", mode: "obd", entries: [.init(request: request, bytes: Data([0x01]))])
        let channel = SerializedELMCommandChannel(transport: transport, encoder: encoder)
        let task = Task { try await channel.execute(request: request, generation: .init(value: 1), timeout: .milliseconds(20)) }
        try await eventually { await transport.writeCount() == 1 }
        await channel.receive(Data("PARTIAL".utf8), generation: .init(value: 1))
        let response = try await task.value

        #expect(response.completion == .timedOut)
        #expect(response.rawBytes == Data("PARTIAL".utf8))
    }

    /// timeout後の遅延responseをqueue済み次commandへ誤対応しません。
    @Test
    func delayedResponseAfterTimeoutCannotCompleteNextCommand() async throws {
        let transport = FakeCommunicationTransport()
        let firstRequest = ELMCommandRequest.standardOBD(.init(purpose: .currentData(parameter: 1)))
        let nextRequest = ELMCommandRequest.standardOBD(.init(purpose: .currentData(parameter: 2)))
        let encoder = VersionedELMCommandAllowlist(version: 1, adapterModel: "fixture", firmwareVersion: "fixture", mode: "obd", entries: [.init(request: firstRequest, bytes: Data([0x01])), .init(request: nextRequest, bytes: Data([0x02]))])
        let channel = SerializedELMCommandChannel(transport: transport, encoder: encoder)
        let first = Task { try await channel.execute(request: firstRequest, generation: .init(value: 1), timeout: .milliseconds(20)) }
        try await eventually { await transport.writeCount() == 1 }
        let second = Task { try await channel.execute(request: nextRequest, generation: .init(value: 1), timeout: .seconds(1)) }
        _ = try await first.value
        await channel.receive(Data("LATE\r>".utf8), generation: .init(value: 1))

        await #expect(throws: CommunicationRuntimeError.malformedResponse) { try await second.value }
        #expect(await transport.writeCount() == 1)
    }

    /// task取消しはpartial Raw付きcancelled応答でwaiterを終了します。
    @Test
    func cancellationFinishesWaiter() async throws {
        let transport = FakeCommunicationTransport()
        let request = ELMCommandRequest.standardOBD(.init(purpose: .currentData(parameter: 1)))
        let encoder = VersionedELMCommandAllowlist(version: 1, adapterModel: "fixture", firmwareVersion: "fixture", mode: "obd", entries: [.init(request: request, bytes: Data([0x01]))])
        let channel = SerializedELMCommandChannel(transport: transport, encoder: encoder)
        let task = Task { try await channel.execute(request: request, generation: .init(value: 1), timeout: .seconds(10)) }
        try await eventually { await transport.writeCount() == 1 }
        await channel.receive(Data("PART".utf8), generation: .init(value: 1))
        task.cancel()
        let response = try await task.value

        #expect(response.completion == .cancelled)
        #expect(response.rawBytes == Data("PART".utf8))
    }

    /// Production unavailable encoderと未許可用途はwrite前に拒否されます。
    @Test
    func commandOutsideAllowlistIsRejectedBeforeWrite() async {
        let transport = FakeCommunicationTransport()
        let channel = SerializedELMCommandChannel(transport: transport, encoder: UnavailableELMCommandEncoder())
        await #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) {
            try await channel.execute(request: .adapterInitializationReset, generation: .init(value: 1), timeout: .seconds(1))
        }
        #expect(await transport.writeCount() == 0)
    }

    /// Adapter resetは専用証拠flagなしにallowlist entryだけで許可されません。
    @Test
    func adapterResetRequiresSeparateTranscriptAuthorization() {
        let encoder = VersionedELMCommandAllowlist(version: 1, adapterModel: "fixture", firmwareVersion: "fixture", mode: "init", entries: [.init(request: .adapterInitializationReset, bytes: Data([0xAA]))])
        #expect(throws: CommunicationRuntimeError.commandNotAllowlisted) { try encoder.encode(.adapterInitializationReset) }
    }

    /// 非同期書込の反映を短い上限内で待ちます。
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
