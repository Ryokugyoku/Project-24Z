import Foundation

/// 認証連携前の単一端末TestFlight pilotで安定したローカルscopeを供給します。
nonisolated struct LocalInstallationScopeProvider: Sendable {
    /// UserDefaultsに保存したscopeを読み、初回だけUUIDを生成します。
    /// - Parameter platform: 現在Platform。
    /// - Returns: 再起動後も同じローカルscope。
    func scope(platform: LocalDeviceScope.Platform) -> LocalDeviceScope {
        let defaults = UserDefaults.standard
        let userScopeID = persistedUUID(key: "project24z.localPilot.userScopeID", defaults: defaults)
        let deviceScopeID = persistedUUID(key: "project24z.localPilot.deviceScopeID", defaults: defaults)
        return LocalDeviceScope(
            userScopeID: userScopeID,
            localDeviceScopeID: deviceScopeID,
            platform: platform
        )
    }

    /// 保存済みUUIDを返し、不在または不正時だけ新しい値を保存します。
    /// - Parameters:
    ///   - key: UserDefaults key。
    ///   - defaults: 保存先。
    /// - Returns: 安定UUID。
    private func persistedUUID(key: String, defaults: UserDefaults) -> UUID {
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString.lowercased(), forKey: key)
        return identifier
    }
}
