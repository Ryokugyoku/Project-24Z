import Foundation

/// 対象Adapter条件まで一致した型付きcommandだけをbytesへ変換します。
nonisolated struct VersionedELMCommandAllowlist: ELMCommandEncoding, Sendable {
    /// 一つの検証済み用途と固定bytesです。
    nonisolated struct Entry: Equatable, Sendable {
        let request: ELMCommandRequest
        let bytes: Data
    }

    let version: Int
    let adapterModel: String
    let firmwareVersion: String
    let mode: String
    private let adapterResetTranscriptVerified: Bool
    private let entries: [Entry]

    /// 検証済みtranscriptから固定したentry集合を作ります。
    /// - Parameters:
    ///   - version: allowlistの形式Version。
    ///   - adapterModel: 証拠対象のAdapter model。
    ///   - firmwareVersion: 証拠対象のfirmware。
    ///   - mode: 証拠対象のAdapter mode。
    ///   - adapterResetTranscriptVerified: Adapter自身のresetが必須かつ検証済みの場合だけ`true`。
    ///   - entries: 型付き用途とexact bytesの対応。
    init(version: Int, adapterModel: String, firmwareVersion: String, mode: String, adapterResetTranscriptVerified: Bool = false, entries: [Entry]) {
        self.version = version
        self.adapterModel = adapterModel
        self.firmwareVersion = firmwareVersion
        self.mode = mode
        self.adapterResetTranscriptVerified = adapterResetTranscriptVerified
        self.entries = entries
    }

    /// 一致する型付きentryだけを返します。
    /// - Parameter request: 上流の用途別Request。
    /// - Returns: transcriptで固定済みのbytes。
    /// - Throws: entryがなければ`commandNotAllowlisted`。
    func encode(_ request: ELMCommandRequest) throws -> Data {
        if request == .adapterInitializationReset, !adapterResetTranscriptVerified {
            throw CommunicationRuntimeError.commandNotAllowlisted
        }
        guard let entry = entries.first(where: { $0.request == request }) else {
            throw CommunicationRuntimeError.commandNotAllowlisted
        }
        return entry.bytes
    }
}
