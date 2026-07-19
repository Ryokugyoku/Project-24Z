import CryptoKit
import Foundation
import Security

/// Keychainのroot keyから用途別鍵を導出して車両識別値を保護します。
nonisolated struct KeychainVehicleSensitiveValueProtector: VehicleSensitiveValueProtecting, Sendable {
    private let service = "Ryokugyoku.Project-24Z.vehicle-evidence-root"
    private let account = "local-install-v1"

    /// AES-256-GCMで平文を認証付き暗号へ封印します。
    /// - Parameter plaintext: Repositoryへ渡す前の短寿命平文。
    /// - Returns: nonce、ciphertext、tagを結合したVersion 1値。
    /// - Throws: Keychainまたは暗号処理が利用不能な場合。
    func encrypt(_ plaintext: Data) throws -> EncryptedVehicleValue {
        let key = try derivedKey(info: Data("vehicle-encryption-v1".utf8))
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw ProtectionError.sealFailed }
        return EncryptedVehicleValue(ciphertext: combined, keyVersion: 1)
    }

    /// 用途分離済みHMAC-SHA256で一意照合Digestを作ります。
    /// - Parameter normalizedValue: 大文字化済み識別値。
    /// - Returns: 32 byte Digest。
    /// - Throws: Keychainまたは鍵導出が利用不能な場合。
    func lookupDigest(for normalizedValue: String) throws -> Data {
        let key = try derivedKey(info: Data("vehicle-lookup-digest-v1".utf8))
        return Data(HMAC<SHA256>.authenticationCode(for: Data(normalizedValue.utf8), using: key))
    }

    /// Keychain rootからHKDFで用途別32 byte鍵を導出します。
    /// - Parameter info: 固定用途ラベル。
    /// - Returns: 用途別SymmetricKey。
    /// - Throws: root keyを取得または作成できない場合。
    private func derivedKey(info: Data) throws -> SymmetricKey {
        let root = SymmetricKey(data: try loadOrCreateRootKey())
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: root,
            salt: Data("Project24Z.vehicle-evidence.hkdf.v1".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    /// 既存root keyを読み、未作成なら暗号学的乱数で一度だけ作成します。
    /// - Returns: 32 byte root key。
    /// - Throws: Keychainまたは乱数API失敗。
    private func loadOrCreateRootKey() throws -> Data {
        if let existing = try readRootKey() { return existing }
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw ProtectionError.randomFailed(status) }
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: bytes,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let existing = try readRootKey() {
            return existing
        }
        guard addStatus == errSecSuccess else { throw ProtectionError.keychain(addStatus) }
        return bytes
    }

    /// Keychainに保存済みのroot keyを読みます。
    /// - Returns: 未作成ならnil、存在すれば32 byte key。
    /// - Throws: 不正長またはKeychain照会失敗。
    private func readRootKey() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw ProtectionError.keychain(status)
        }
        return data
    }

    /// 機密情報を含まない保護境界Errorです。
    private enum ProtectionError: Error {
        case randomFailed(OSStatus)
        case keychain(OSStatus)
        case sealFailed
    }
}
