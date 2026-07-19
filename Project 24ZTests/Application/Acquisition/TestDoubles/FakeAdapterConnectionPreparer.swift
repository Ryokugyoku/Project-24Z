@testable import Project_24Z

/// 役割別Adapter準備の成功・失敗Fakeです。
final class FakeAdapterConnectionPreparer: AdapterConnectionPreparing, @unchecked Sendable {
    /// 準備する役割です。
    let role: CommunicationRole

    /// 成功時の物理Adapter参照です。
    let reference: AdapterReference

    /// 呼出し順序Recorderです。
    let recorder: AcquisitionStartEventRecorder

    /// 次の準備で投げる失敗です。
    var failure: AcquisitionStartFailure?

    /// close回数です。
    private(set) var closeCount = 0

    /// Fakeを構成します。
    /// - Parameters:
    ///   - role: 固定役割。
    ///   - reference: 成功時参照。
    ///   - recorder: 共通Recorder。
    init(role: CommunicationRole, reference: AdapterReference, recorder: AcquisitionStartEventRecorder) {
        self.role = role
        self.reference = reference
        self.recorder = recorder
    }

    /// 準備Eventを記録してfixture結果を返します。
    /// - Parameters:
    ///   - candidate: 使用しない候補。
    ///   - binding: 使用しないbinding。
    ///   - generation: 返却するGeneration。
    /// - Returns: 準備済み接続。
    /// - Throws: 設定済み失敗。
    func prepare(candidate: DefaultAdapterCandidate, binding: VerifiedAdapterBinding?, generation: ConnectionGeneration) async throws -> PreparedAdapterConnection {
        recorder.append(role == .primaryOBD ? "prepare-primary" : "prepare-secondary")
        if let failure { throw failure }
        return .init(role: role, adapterReference: reference, generation: generation)
    }

    /// closeを記録します。
    func close() async {
        closeCount += 1
        recorder.append(role == .primaryOBD ? "close-primary" : "close-secondary")
    }
}
