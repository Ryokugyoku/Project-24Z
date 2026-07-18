import Foundation

/// 暗号化とDigest計算を終えた登録根拠識別子です。
nonisolated struct VehicleIdentifierEvidence: Equatable, Sendable {
    /// 登録可能な識別子種別です。
    enum Kind: String, Equatable, Hashable, Sendable {
        /// ISO VINです。
        case vin
        /// 国内車台番号です。
        case domesticChassisNumber = "domestic_chassis_number"
    }

    /// 識別子行のUUIDです。
    let identifierID: UUID
    /// 識別子種別です。
    let kind: Kind
    /// 正規化値の暗号文です。
    let encryptedNormalizedValue: EncryptedVehicleValue
    /// ユーザー別・用途別鍵で計算済みの32 byte Digestです。
    let lookupDigest: Data
    /// Digest鍵Versionです。
    let digestKeyVersion: Int
}
