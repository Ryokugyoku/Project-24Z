import Foundation

/// 文字列化不能部分を含むELM応答を非破壊で保持します。
nonisolated struct ELMResponseEnvelope: Equatable, Sendable {
    /// 応答終端の理由です。
    enum Completion: Equatable, Sendable { case prompt; case timedOut; case cancelled; case disconnected }
    /// Rawを失わない安定分類です。
    enum Classification: Equatable, Sendable { case dataCandidate; case searchingProgress; case noData; case stopped; case busInitialization; case unknownStatus; case malformed }

    let commandSequence: UInt64
    let correlationID: UUID
    let generation: ConnectionGeneration
    let rawBytes: Data
    let promptRange: Range<Int>?
    let classification: Classification
    let completion: Completion
}
