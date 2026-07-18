#if os(macOS)
import SwiftUI

/// macOS専用の車両登録・管理画面を表示します。
struct MacOSVehicleManagementView: View {
    /// Applicationが公開する車両登録画面Modelです。
    @ObservedObject var model: VehicleRegistrationModel

    /// 新規登録時に利用者が任意入力する表示名です。
    @State private var displayName = ""

    /// Tab移動とキーボード登録で使用する表示名入力Focusです。
    @FocusState private var isDisplayNameFocused: Bool

    /// 広いdetailでは内容自体を読みやすくし、狭い幅では縦にスクロールできる画面です。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusGroup
                vehicleGroup
                sessionGroup
                actionGroup
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("車両管理")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Label(model.state.display.title, systemImage: stateSystemImage)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("現在の状態、\(model.state.display.title)")
            }
        }
        .accessibilityIdentifier("project24z.vehicleRegistration.macos")
    }

    /// 現在の状態、説明、進捗、利用不能理由をまとめて表示します。
    private var statusGroup: some View {
        GroupBox("現在の状態") {
            VStack(alignment: .leading, spacing: 12) {
                Label(model.state.display.title, systemImage: stateSystemImage)
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel("現在の状態、\(model.state.display.title)")
                    .accessibilityIdentifier("project24z.vehicleRegistration.status")

                Text(model.state.display.message)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = model.state.display.progress {
                    ProgressView(value: progress) {
                        Text("進捗")
                    }
                    .accessibilityIdentifier("project24z.vehicleRegistration.progress")
                }

                if let reason = model.state.display.unavailableReason {
                    informationRow(
                        label: "理由",
                        value: reason,
                        identifier: "project24z.vehicleRegistration.unavailableReason"
                    )
                }

                if let disabledReason = model.state.display.actionDisabledReason {
                    informationRow(
                        label: "操作できない理由",
                        value: disabledReason,
                        identifier: "project24z.vehicleRegistration.actionDisabledReason"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    /// mask済み識別子などの安全な車両情報をGridで表示します。
    @ViewBuilder
    private var vehicleGroup: some View {
        if hasVehicleDetails {
            GroupBox("車両情報") {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        if let vehicleName = model.state.display.vehicleDisplayName {
                            informationGridRow(label: "表示名", value: vehicleName)
                        }
                        if let maskedIdentifier = model.state.display.maskedIdentifier {
                            informationGridRow(
                                label: "識別子",
                                value: maskedIdentifier,
                                identifier: "project24z.vehicleRegistration.maskedIdentifier"
                            )
                        }
                        if let adapterName = model.state.display.adapterDisplayName {
                            informationGridRow(label: "Adapter", value: adapterName)
                        }
                    }

                    lifecycleNotice
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    /// archived、Conflict、binding pendingを通常登録と区別して表示します。
    @ViewBuilder
    private var lifecycleNotice: some View {
        switch model.state {
        case .duplicateCandidate(let candidate) where candidate.lifecycle == .archived:
            Label("アーカイブ済み候補です。復元は別の確認操作です。", systemImage: "archivebox")
                .accessibilityIdentifier("project24z.vehicleRegistration.archivedCandidate")
        case .archivedRestoreRequired:
            Label("Scan保持済み・復元未完了です。登録済みではありません。", systemImage: "arrow.uturn.backward.circle")
                .accessibilityIdentifier("project24z.vehicleRegistration.restoreRequired")
        case .restoringArchivedVehicle:
            Label("アーカイブ復元中です。通常の新規登録処理ではありません。", systemImage: "arrow.clockwise.circle")
                .accessibilityIdentifier("project24z.vehicleRegistration.restoringArchivedVehicle")
        case .conflict:
            Label("競合を自動解決しません。", systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("project24z.vehicleRegistration.conflict")
        case .registered(let registered) where registered.sessionBindingState == .pending:
            Label("車両登録済み・Session所属待ちです。", systemImage: "link.badge.plus")
                .accessibilityIdentifier("project24z.vehicleRegistration.bindingPending")
        default:
            EmptyView()
        }
    }

    /// 現在Sessionを保持している状態を独立して表示します。
    private var sessionGroup: some View {
        GroupBox("Acquisition Session") {
            Text(model.state.display.sessionSummary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .accessibilityIdentifier("project24z.vehicleRegistration.sessionSummary")
        }
    }

    /// 状態に対応する型付きActionとキーボード操作を表示します。
    @ViewBuilder
    private var actionGroup: some View {
        GroupBox("操作") {
            Form {
                switch model.state {
                case .disconnected(let disconnected):
                    disconnectedActions(disconnected)
                case .connecting(let display), .identifying(let display):
                    cancellationButton(title: "取り消す", display: display)
                case .adapterChecking(let display):
                    cancellationButton(title: "確認を取り消す", display: display)
                case .identificationUnavailable(let display), .failed(let display):
                    actionButton("識別を再試行", action: .retryIdentification(revision: display.revision))
                    unassignedSessionButtons(display: display)
                case .duplicateCandidate(let candidate):
                    identifiedActionButton(
                        candidate.lifecycle == .active ? "登録済み車両を使用" : "アーカイブ候補を確認",
                        display: candidate.display,
                        action: {
                            .selectExistingVehicleCandidate(
                                identifier: $0,
                                revision: candidate.display.revision
                            )
                        }
                    )
                case .archivedRestoreRequired(let candidate):
                    identifiedActionButton(
                        "アーカイブ車両を復元",
                        display: candidate.display,
                        action: {
                            .confirmArchivedVehicleRestore(
                                identifier: $0,
                                lifecycleRevision: candidate.lifecycleRevision,
                                revision: candidate.display.revision
                            )
                        }
                    )
                    unassignedSessionButtons(display: candidate.display)
                case .restoringArchivedVehicle(let display):
                    cancellationButton(title: "復元を取り消す", display: display)
                case .conflict(let display):
                    identifiedActionButton(
                        "競合内容を確認",
                        display: display,
                        action: { .reviewConflict(identifier: $0, revision: display.revision) }
                    )
                    unassignedSessionButtons(display: display)
                case .registrationReady(let display):
                    TextField("車両の表示名（任意）", text: $displayName)
                        .focused($isDisplayNameFocused)
                        .onSubmit {
                            isDisplayNameFocused = false
                            model.perform(
                                .confirmRegistration(
                                    displayName: displayName.isEmpty ? nil : displayName,
                                    revision: display.revision
                                )
                            )
                        }
                        .accessibilityIdentifier("project24z.vehicleRegistration.displayName")
                    actionButton(
                        "車両を登録",
                        action: .confirmRegistration(
                            displayName: displayName.isEmpty ? nil : displayName,
                            revision: display.revision
                        )
                    )
                case .registering(let display):
                    unavailableActionNotice(display: display)
                case .registered(let registered) where registered.sessionBindingState == .pending:
                    identifiedActionButton(
                        "Session所属を再試行",
                        display: registered.display,
                        action: { .retrySessionBinding(identifier: $0, revision: registered.display.revision) }
                    )
                case .registered(let registered):
                    identifiedActionButton(
                        "Sessionを終了",
                        display: registered.display,
                        action: { .endSession(identifier: $0, revision: registered.display.revision) }
                    )
                case .blocked:
                    Button("接続を開始") {}
                        .disabled(true)
                        .accessibilityLabel("接続を開始、現在利用できません")
                        .accessibilityIdentifier("project24z.vehicleRegistration.primaryAction")
                }
            }
            .formStyle(.grouped)
            .padding(.top, 4)
        }
    }

    /// 安全な車両詳細値が一つ以上あるかを返します。
    private var hasVehicleDetails: Bool {
        model.state.display.vehicleDisplayName != nil
            || model.state.display.maskedIdentifier != nil
            || model.state.display.adapterDisplayName != nil
            || requiresLifecycleNotice
    }

    /// 通常登録と区別する注意表示が必要かを返します。
    private var requiresLifecycleNotice: Bool {
        switch model.state {
        case .archivedRestoreRequired, .restoringArchivedVehicle, .conflict:
            true
        case .duplicateCandidate(let candidate):
            candidate.lifecycle == .archived
        case .registered(let registered):
            registered.sessionBindingState == .pending
        default:
            false
        }
    }

    /// 現在状態をVoiceOverでも識別しやすい標準シンボルへ変換します。
    private var stateSystemImage: String {
        switch model.state {
        case .connecting, .adapterChecking, .identifying, .registering:
            "progress.indicator"
        case .duplicateCandidate(let candidate) where candidate.lifecycle == .archived:
            "archivebox"
        case .archivedRestoreRequired:
            "archivebox"
        case .restoringArchivedVehicle:
            "arrow.clockwise.circle"
        case .conflict, .failed:
            "exclamationmark.triangle"
        case .registered(let registered) where registered.sessionBindingState == .pending:
            "link.badge.plus"
        case .registered:
            "checkmark.circle"
        case .blocked, .identificationUnavailable:
            "nosign"
        default:
            "car"
        }
    }

    /// 接続前に安全なTransport／Adapter候補の選択と接続開始Actionを表示します。
    /// - Parameter disconnected: Endpoint秘密IDを含まない接続前Presentation。
    @ViewBuilder
    private func disconnectedActions(
        _ disconnected: VehicleRegistrationDisconnectedPresentation
    ) -> some View {
        if disconnected.transportOptions.isEmpty {
            Text("利用可能な接続候補がありません。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(disconnected.transportOptions.enumerated()), id: \.offset) { _, option in
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Label(
                            option.displayName,
                            systemImage: option.isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        Button("Adapterを選択") {
                            model.perform(
                                .selectAdapter(
                                    identifier: option.adapterSelection,
                                    revision: disconnected.display.revision
                                )
                            )
                        }
                        .accessibilityIdentifier("project24z.vehicleRegistration.selectAdapter")
                    }
                    GridRow {
                        Text("")
                        Button("この接続方法で開始") {
                            model.perform(
                                .startConnection(
                                    transportSelection: option.transportSelection,
                                    revision: disconnected.display.revision
                                )
                            )
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("project24z.vehicleRegistration.startConnection")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    /// 取消可能境界内にある状態だけcancel Actionを表示します。
    /// - Parameters:
    ///   - title: 状態固有の取消ボタン名。
    ///   - display: 取消可能境界を含む安全な表示値。
    @ViewBuilder
    private func cancellationButton(
        title: String,
        display: VehicleRegistrationDisplayValues
    ) -> some View {
        if display.isCancellationAvailable {
            actionButton(
                title,
                action: .cancelConnection(revision: display.revision),
                shortcut: .cancelAction
            )
        } else {
            unavailableActionNotice(display: display)
        }
    }

    /// 現在Stateに公開可能Actionがない理由を表示します。
    /// - Parameter display: 安全な無効理由を含む表示値。
    @ViewBuilder
    private func unavailableActionNotice(display: VehicleRegistrationDisplayValues) -> some View {
        if let reason = display.actionDisabledReason {
            Text(reason)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("project24z.vehicleRegistration.inlineActionDisabledReason")
        } else {
            Text("現在実行できる操作はありません。")
                .foregroundStyle(.secondary)
        }
    }

    /// 説明値を横幅に応じて折り返す行として表示します。
    /// - Parameters:
    ///   - label: 値の意味を示す見出し。
    ///   - value: 安全な表示値。
    ///   - identifier: VoiceOverとUIテスト用の安定識別子。
    private func informationRow(label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// 車両情報Gridへ安全な表示値を一行追加します。
    /// - Parameters:
    ///   - label: 値の意味を示す見出し。
    ///   - value: 安全な表示値。
    ///   - identifier: VoiceOverとUIテスト用の安定識別子。
    @ViewBuilder
    private func informationGridRow(
        label: String,
        value: String,
        identifier: String? = nil
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "project24z.vehicleRegistration.informationRow")
    }

    /// 不透明識別子がある場合だけ状態固有Actionボタンを表示します。
    /// - Parameters:
    ///   - title: ボタンの表示名。
    ///   - display: Action参照とrevisionを含む安全な表示値。
    ///   - action: 不透明識別子から型付きActionを生成する処理。
    @ViewBuilder
    private func identifiedActionButton(
        _ title: String,
        display: VehicleRegistrationDisplayValues,
        action: @escaping (VehicleRegistrationPresentationIdentifier) -> VehicleRegistrationAction
    ) -> some View {
        if let identifier = display.actionIdentifier {
            actionButton(title, action: action(identifier))
        } else {
            Button(title) {}
                .disabled(true)
                .accessibilityIdentifier("project24z.vehicleRegistration.primaryAction")
        }
    }

    /// 車両未割当のままSessionを継続または終了する操作を表示します。
    /// - Parameter display: Session参照とrevisionを含む安全な表示値。
    @ViewBuilder
    private func unassignedSessionButtons(display: VehicleRegistrationDisplayValues) -> some View {
        if let identifier = display.actionIdentifier {
            actionButton(
                "未割当のまま継続",
                action: .continueSessionUnassigned(identifier: identifier, revision: display.revision),
                identifier: "project24z.vehicleRegistration.continueUnassigned",
                shortcut: nil
            )
            actionButton(
                "Sessionを終了",
                action: .endSession(identifier: identifier, revision: display.revision),
                identifier: "project24z.vehicleRegistration.endSession",
                shortcut: nil
            )
        }
    }

    /// 型付きActionをModelへ通知するキーボード対応ボタンを生成します。
    /// - Parameters:
    ///   - title: ボタンの表示名。
    ///   - action: 通知する型付きAction。
    ///   - identifier: UIテストとVoiceOver確認用の安定識別子。
    ///   - shortcut: macOSのキーボードショートカット。
    @ViewBuilder
    private func actionButton(
        _ title: String,
        action: VehicleRegistrationAction,
        identifier: String = "project24z.vehicleRegistration.primaryAction",
        shortcut: KeyboardShortcut? = .defaultAction
    ) -> some View {
        if let shortcut {
            Button(title) {
                model.perform(action)
            }
            .keyboardShortcut(shortcut)
            .accessibilityIdentifier(identifier)
        } else {
            Button(title) {
                model.perform(action)
            }
            .accessibilityIdentifier(identifier)
        }
    }
}

#if DEBUG
/// Production Compositionを経由しないblocked状態のmacOS Previewです。
#Preview("macOS Blocked") {
    MacOSVehicleManagementView(model: VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.blocked))
        .frame(width: 900, height: 640)
}

/// Conflictを通常登録と区別するmacOS Previewです。
#Preview("macOS Conflict") {
    MacOSVehicleManagementView(model: VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.conflict))
        .frame(width: 900, height: 640)
}

/// archived復元中を通常登録中と区別するmacOS Previewです。
#Preview("macOS Restoring Archived Vehicle") {
    MacOSVehicleManagementView(model: VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.restoringArchivedVehicle))
        .frame(width: 900, height: 640)
}

/// archived復元失敗後の復元待ちを明示するmacOS Previewです。
#Preview("macOS Restore Failed") {
    MacOSVehicleManagementView(model: VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.restoreFailed))
        .frame(width: 900, height: 640)
}

/// Session所属待ちを明示するmacOS Previewです。
#Preview("macOS Binding Pending") {
    MacOSVehicleManagementView(model: VehicleRegistrationModel(previewState: VehicleRegistrationPreviewFixtures.sessionBindingPending))
        .frame(width: 900, height: 640)
}
#endif
#endif
