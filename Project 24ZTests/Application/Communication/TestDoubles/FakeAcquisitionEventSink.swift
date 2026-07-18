@testable import Project_24Z

/// Runtime受理と保存pipeline失敗を分離して観測するSink Fakeです。
actor FakeAcquisitionEventSink: AcquisitionEventSink {
    private(set) var events: [CommunicationRuntimeEvent] = []
    var shouldFail = false

    /// 保存受理失敗の注入状態を変更します。
    /// - Parameter enabled: 失敗させる場合は`true`。
    func setFailure(_ enabled: Bool) { shouldFail = enabled }

    /// Eventを記録するか保存不能を注入します。
    /// - Parameter event: Runtimeから受け取ったEvent。
    /// - Throws: `shouldFail`の場合は`storageUnavailable`。
    func accept(_ event: CommunicationRuntimeEvent) async throws {
        if shouldFail { throw CommunicationRuntimeError.storageUnavailable }
        events.append(event)
    }

    /// 受理済みEvent件数を返します。
    /// - Returns: 受理件数。
    func eventCount() -> Int { events.count }

    /// 最後に受理したEventを返します。
    /// - Returns: Eventがなければ`nil`。
    func lastEvent() -> CommunicationRuntimeEvent? { events.last }
}
