import Foundation

/// batchまたはsingle RequestのRawを失わないPolling結果です。
nonisolated struct PIDPollingResponse: Equatable, Sendable {
    /// Request方式です。
    enum RequestKind: Equatable, Sendable {
        case batch
        case single
    }

    /// Request方式です。
    let requestKind: RequestKind
    /// 対象Identityです。
    let identities: [PIDSignalIdentity]
    /// 完全なRaw responseです。
    let rawResponse: Data
    /// 個別結果へ安全に分離できたかを示します。
    let isUsable: Bool
}
