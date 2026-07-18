import Foundation

/// 一接続中に応答した一つのECUの終端Snapshotです。
nonisolated struct ECUObservationSnapshot: Equatable, Sendable {
    /// 応答元アドレスの形式です。
    enum AddressFormat: String, Equatable, Sendable {
        case can11Bit = "can_11_bit"
        case can29Bit = "can_29_bit"
        case iso9141
        case iso14230
        case unknown
    }

    /// ECU観測行UUIDです。
    let observationID: UUID
    /// スキャン内の0始まり応答順です。
    let ordinal: Int
    /// 応答元アドレス形式です。
    let addressFormat: AddressFormat
    /// 応答元アドレスのbytesです。
    let responderAddress: Data
    /// このECUから得た全識別値です。
    let values: [ECUIdentificationValueSnapshot]
}
