import Foundation

/// 型付きELM用途をVersion付きallowlistのbytesへ写像する能力です。
nonisolated protocol ELMCommandEncoding: Sendable {
    /// Requestに対応する許可済みbytesを返します。
    /// - Parameter request: 任意文字列を含まない用途別Request。
    /// - Returns: 対象model／firmware／mode／Versionで固定されたbytes。
    /// - Throws: 一致する許可entryがない場合の拒否。
    func encode(_ request: ELMCommandRequest) throws -> Data
}
