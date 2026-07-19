#if os(iOS)
import SwiftUI

/// iOSのホーム画面を表示します。
struct IOSHomeView: View {
    /// Composition Rootから注入されたダッシュボードModelです。
    @EnvironmentObject private var model: DashboardModel

    /// Primary未設定時に設定画面へ移動するPlatform Navigation Actionです。
    let openConnectionSettings: () -> Void

    /// iOS専用ダッシュボードを表示します。
    var body: some View {
        Form {
            Section("ログ収集") {
                Text(model.state.statusMessage)
                Button(model.state.primaryAction.title) {
                    performPrimaryAction(model.state.primaryAction.action)
                }
                .disabled(!model.state.primaryAction.isEnabled)
                .accessibilityLabel(model.state.primaryAction.accessibilityLabel)
                .accessibilityHint(model.state.primaryAction.accessibilityHint)

                if case .awaitingPIDOnlyConfirmation = model.state.acquisitionState {
                    Button("PIDのみで開始") {
                        Task { await model.confirmPIDOnlyStart() }
                    }
                    Button("キャンセル", role: .cancel) {
                        Task { await model.cancelStart() }
                    }
                }
            }
        }
        .navigationTitle("ホーム")
        .accessibilityIdentifier("project24z.home")
        .task { model.load() }
    }

    /// Applicationが導出した主ActionをPlatform操作へ接続します。
    /// - Parameter action: 現在Stateと一致する型付きAction。
    private func performPrimaryAction(_ action: DashboardAction) {
        switch action {
        case .openConnectionSettings:
            openConnectionSettings()
        case .startAcquisition:
            Task { await model.startAcquisition() }
        case .stopAcquisition:
            Task { await model.stopAcquisition() }
        case .none:
            break
        }
    }
}
#endif
