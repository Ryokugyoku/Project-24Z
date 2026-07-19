import Foundation

/// 認証済みUserと一台のローカル端末を組み合わせた設定境界です。
nonisolated struct LocalDeviceScope: Equatable, Hashable, Sendable {
    /// 実行Platformを端末間で混同しない分類です。
    enum Platform: String, Equatable, Sendable {
        case iOS
        case macOS
    }

    /// 認証境界が供給するUser Scopeです。
    let userScopeID: UUID

    /// 承認済み端末Identity境界が供給するローカル端末Scopeです。
    let localDeviceScopeID: UUID

    /// この設定を所有するPlatformです。
    let platform: Platform
}
