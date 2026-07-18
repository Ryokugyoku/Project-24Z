import Foundation

/// 一つのECU別PID候補の探索結果です。
nonisolated struct PIDSupportObservation: Equatable, Sendable {
    /// support表明と値取得を混同しない状態です。
    enum State: Equatable, Sendable {
        case declaredSupported
        case valueObserved
        case declaredButValueFailed
        case explicitlyUnsupported
        case noData
        case negativeResponse
        case timedOut
        case malformed
        case unknown
    }

    /// ECU別PID Identityです。
    let identity: PIDSignalIdentity
    /// 探索結果です。
    let state: State
    /// 結果を根拠付けるRaw応答です。
    let rawResponse: Data
}
