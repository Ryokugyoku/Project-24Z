/// 接続設定画面が描画する役割別の確定状態です。
nonisolated struct ConnectionSettingsRolePresentation: Equatable, Sendable {
    /// 対象Adapter役割です。
    let role: CommunicationRole

    /// 保存済み候補。未設定なら`nil`です。
    let candidate: DefaultAdapterCandidate?

    /// 探索または保存中かを示します。
    let isBusy: Bool

    /// 利用者へ示す安定した失敗説明です。
    let failureMessage: String?
}

/// 接続設定画面が描画する共有Application Stateです。
nonisolated struct ConnectionSettingsPresentationState: Equatable, Sendable {
    /// Primaryの確定状態です。
    let primary: ConnectionSettingsRolePresentation

    /// Secondaryの確定状態です。
    let secondary: ConnectionSettingsRolePresentation

    /// 現在候補選択中の役割です。
    let selectingRole: CommunicationRole?

    /// 接続していない探索候補です。
    let discoveredCandidates: [ConnectionEndpointCandidate]

    /// 候補探索の安定した案内です。
    let discoveryMessage: String?

    /// Production能力がHard Gate未達である旨です。
    let productionAvailabilityMessage: String?

    /// 初期未設定状態を生成します。
    /// - Parameter productionAvailabilityMessage: Productionで利用不可の場合の説明。
    /// - Returns: 両役割が未設定のState。
    static func empty(productionAvailabilityMessage: String? = nil) -> Self {
        Self(
            primary: .init(role: .primaryOBD, candidate: nil, isBusy: false, failureMessage: nil),
            secondary: .init(role: .secondaryRawCAN, candidate: nil, isBusy: false, failureMessage: nil),
            selectingRole: nil,
            discoveredCandidates: [],
            discoveryMessage: nil,
            productionAvailabilityMessage: productionAvailabilityMessage
        )
    }
}
