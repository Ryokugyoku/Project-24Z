/// ダッシュボード主操作の文言・Accessibility・Actionを同じ状態から導出します。
nonisolated struct DashboardPrimaryActionPresentation: Equatable, Sendable {
    /// ボタン表示文言です。
    let title: String

    /// VoiceOver labelです。
    let accessibilityLabel: String

    /// VoiceOver hintです。
    let accessibilityHint: String

    /// 二重操作を防ぐ有効性です。
    let isEnabled: Bool

    /// ボタンが通知する型付きActionです。
    let action: DashboardAction
}

/// ダッシュボードの共有Application Stateです。
nonisolated struct DashboardPresentationState: Equatable, Sendable {
    /// Primaryが端末ローカルに設定済みかを示します。
    let hasPrimaryCandidate: Bool

    /// 開始Coordinatorの現在状態です。
    let acquisitionState: AcquisitionStartState

    /// 主操作Presentationです。
    let primaryAction: DashboardPrimaryActionPresentation

    /// 利用者が次に取れるActionとデータ状態を示す説明です。
    let statusMessage: String
}

/// ダッシュボードから通知できる操作です。
nonisolated enum DashboardAction: Equatable, Sendable {
    case openConnectionSettings
    case startAcquisition
    case stopAcquisition
    case none
}
