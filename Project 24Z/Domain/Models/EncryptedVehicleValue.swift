import Foundation

/// 暗号方式をData層の外へ公開せず、準備済み暗号文と鍵Versionを運ぶ値です。
nonisolated struct EncryptedVehicleValue: Equatable, Sendable {
    /// 認証付き暗号で封印済みの値です。
    let ciphertext: Data

    /// 暗号化に使用した鍵Versionです。
    let keyVersion: Int
}
