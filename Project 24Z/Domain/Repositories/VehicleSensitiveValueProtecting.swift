import Foundation

/// 車両識別値をRepository投入前に用途別鍵で保護する境界です。
nonisolated protocol VehicleSensitiveValueProtecting: Sendable {
    /// 平文を認証付き暗号へ封印します。
    /// - Parameter plaintext: 短寿命の平文bytes。
    /// - Returns: 鍵Version付き暗号文。
    /// - Throws: Keychain、乱数、暗号処理が利用不能な場合。
    func encrypt(_ plaintext: Data) throws -> EncryptedVehicleValue

    /// 正規化識別値から用途分離済み32 byte keyed digestを作ります。
    /// - Parameter normalizedValue: 正規化済み識別値。
    /// - Returns: 32 byte HMAC-SHA256。
    /// - Throws: Keychainまたは鍵導出が利用不能な場合。
    func lookupDigest(for normalizedValue: String) throws -> Data
}
