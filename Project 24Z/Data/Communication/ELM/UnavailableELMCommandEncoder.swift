import Foundation

/// Hard Gate未達のProduction経路で全command生成を拒否します。
nonisolated struct UnavailableELMCommandEncoder: ELMCommandEncoding, Sendable {
    /// command bytesを推測せず常に拒否します。
    /// - Parameter request: 拒否対象の用途別Request。
    /// - Returns: この実装は値を返しません。
    /// - Throws: 常に`commandNotAllowlisted`。
    func encode(_ request: ELMCommandRequest) throws -> Data {
        throw CommunicationRuntimeError.commandNotAllowlisted
    }
}
