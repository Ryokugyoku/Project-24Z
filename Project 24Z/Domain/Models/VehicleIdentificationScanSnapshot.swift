import Foundation

/// 一OBD接続から確定した、追記専用の最終識別Snapshotです。
nonisolated struct VehicleIdentificationScanSnapshot: Equatable, Sendable {
    /// スキャンの終端状態です。
    enum Status: String, Equatable, Sendable {
        case completed
        case incomplete
        case failed
    }

    /// スキャン全体のDecode状態です。
    enum DecodeState: String, Equatable, Sendable {
        case decoded
        case partiallyDecoded = "partially_decoded"
        case undecodable
    }

    /// 車両識別子のValidation状態です。
    enum IdentityValidationState: String, Equatable, Sendable {
        case valid
        case invalid
        case unavailable
    }

    /// スキャン行UUIDです。
    let scanID: UUID
    /// 一接続一件制約に使うOBD接続UUIDです。
    let obdConnectionID: UUID
    /// 非機密な通信経路コードです。
    let transportKind: String
    /// 診断プロトコルの安定コードです。
    let diagnosticProtocolKind: String
    /// 秘密情報を含まないAdapter参照です。
    let adapterReferenceID: String
    /// Decode規則bundle Versionです。
    let decoderVersion: String
    /// 正規化・Validation規則bundle Versionです。
    let normalizationVersion: String
    /// スキャンの終端状態です。
    let status: Status
    /// Decode状態です。
    let decodeState: DecodeState
    /// 識別子Validation状態です。
    let identityValidationState: IdentityValidationState
    /// incompleteまたはfailedの非機密な終端理由コードです。
    let terminationReasonCode: String?
    /// 識別開始日時です。
    let startedAt: Date
    /// 終端確定日時です。
    let finishedAt: Date
    /// 応答した全ECUです。
    let observations: [ECUObservationSnapshot]
}
