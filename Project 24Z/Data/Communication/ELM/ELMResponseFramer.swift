import Foundation

/// 分割byte streamからprompt終端の応答単位をRawのまま切り出します。
nonisolated struct ELMResponseFramer: Sendable {
    private var buffer = Data()

    /// 新しいbytesを追加し、最初のpromptまでが揃えば応答を返します。
    /// - Parameter bytes: Transportから到着した未加工bytes。
    /// - Returns: promptを含むRaw応答とprompt範囲。未完なら`nil`。
    mutating func append(_ bytes: Data) -> (raw: Data, promptRange: Range<Int>)? {
        buffer.append(bytes)
        guard let promptIndex = buffer.firstIndex(of: 0x3E) else { return nil }
        let end = buffer.index(after: promptIndex)
        let raw = Data(buffer[..<end])
        let offset = buffer.distance(from: buffer.startIndex, to: promptIndex)
        buffer.removeSubrange(..<end)
        return (raw, offset..<(offset + 1))
    }

    /// timeout、取消し、切断時のpartial bytesを失わず取り出します。
    /// - Returns: 現在までの全Raw bytes。
    mutating func drainPartial() -> Data {
        defer { buffer.removeAll(keepingCapacity: false) }
        return buffer
    }
}
