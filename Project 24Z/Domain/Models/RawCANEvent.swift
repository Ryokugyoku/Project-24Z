import Foundation

/// Raw CAN受信bytesと解析状態を切り詰めず保持します。
nonisolated struct RawCANEvent: Equatable, Sendable {
    /// CAN識別子形式です。
    enum IdentifierFormat: Equatable, Sendable { case standard11Bit; case extended29Bit; case unknown }
    /// 解析結果です。
    enum ParseState: Equatable, Sendable { case parsed; case partial; case malformed; case unknownFormat }

    let identifier: UInt32?
    let identifierFormat: IdentifierFormat
    let dlc: UInt8?
    let payload: Data
    let rawBytes: Data
    let parseState: ParseState
    let generation: ConnectionGeneration
}
