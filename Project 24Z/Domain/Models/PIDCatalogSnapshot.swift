/// 根拠とVersionが固定されたPID Catalogの利用可否Snapshotです。
nonisolated struct PIDCatalogSnapshot: Equatable, Sendable {
    /// CatalogをProductionで利用できるかを表します。
    enum Availability: Equatable, Sendable {
        /// 一次根拠と互換性が承認された閉じたCatalogです。
        case approved
        /// 根拠または互換性が未確定で、定義を利用できません。
        case blocked
    }

    /// 一つの承認済み型付きRequest定義です。
    struct Entry: Equatable, Hashable, Sendable {
        /// Requestが対象とする信号Identityです。
        let identity: PIDSignalIdentity
        /// Pollingの相対優先度hintです。
        let priority: AdaptivePollingPriority
    }

    /// Catalog bundle Versionです。
    let version: String
    /// Production利用可否です。
    let availability: Availability
    /// Version内の閉じた定義集合です。
    let entries: [Entry]

    /// Production探索に使用できる定義だけを返します。
    /// - Returns: 承認済みなら全定義、未確定なら空配列。
    var approvedEntries: [Entry] {
        availability == .approved ? entries : []
    }
}
