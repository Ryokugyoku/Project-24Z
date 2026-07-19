#if os(iOS)
import SwiftUI

/// iOS専用の端末ローカル接続設定画面です。
struct IOSConnectionSettingsView: View {
    /// Applicationの候補探索・保存状態です。
    @EnvironmentObject private var model: ConnectionSettingsModel

    /// iOSでは未検証USBを出さず、BluetoothとRaw CANを開発中として非活性表示します。
    var body: some View {
        Form {
            if let message = model.state.productionAvailabilityMessage {
                Section("現在の利用可否") { Label(message, systemImage: "exclamationmark.triangle") }
            }
            roleSection(model.state.primary, required: true)
            roleSection(model.state.secondary, required: false)
        }
        .navigationTitle("接続設定")
        .task { await model.perform(.load) }
        .onDisappear { Task { await model.perform(.cancelDiscovery) } }
        .sheet(isPresented: selectionPresented) { IOSConnectionCandidateSelectionView(model: model) }
    }

    /// 一役割の確定値と操作を標準Sectionで表示します。
    /// - Parameters:
    ///   - roleState: Applicationが公開する役割状態。
    ///   - required: Primaryの必須表示か。
    /// - Returns: iOS専用Section。
    private func roleSection(_ roleState: ConnectionSettingsRolePresentation, required: Bool) -> some View {
        Section(required ? "OBD・PID用（必須）" : "Raw CAN受信専用（任意）") {
            if roleState.role == .secondaryRawCAN {
                Label("開発中", systemImage: "hammer")
                    .foregroundStyle(.secondary)
            }
            if let candidate = roleState.candidate {
                LabeledContent("既定候補", value: candidate.endpoint.displayName)
                LabeledContent("接続方式", value: transportName(candidate.endpoint.transportKind))
                Text("表示名はAdapter Identity確認済みの証拠ではありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Bluetoothデバイスへ変更") {
                    Task { await model.perform(.beginDiscovery(role: roleState.role, transportKind: .bluetoothLE)) }
                }
                .disabled(true)
                Button("既定候補を解除", role: .destructive) {
                    Task { await model.perform(.clearDefault(role: roleState.role)) }
                }
            } else {
                Text("未設定")
                Button("Bluetoothデバイスを選択") {
                    Task { await model.perform(.beginDiscovery(role: roleState.role, transportKind: .bluetoothLE)) }
                }
                .disabled(true)
            }
            Text("Bluetooth接続は開発中のため、現在は選択できません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if roleState.role == .secondaryRawCAN {
                Text("CAN接続は開発中です。Primaryとは別の物理Adapterと受信専用の実車証拠が揃うまで利用できません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if roleState.isBusy { ProgressView() }
            if let failure = roleState.failureMessage { Text(failure).foregroundStyle(.red) }
        }
    }

    /// 選択Stateをsheet表示Bindingへ変換します。
    private var selectionPresented: Binding<Bool> {
        Binding(get: { model.state.selectingRole != nil }, set: { shown in
            if !shown { Task { await model.perform(.cancelDiscovery) } }
        })
    }

    /// Transport種別の非機密表示名を返します。
    /// - Parameter kind: 内部で分離されたTransport種別。
    /// - Returns: 利用者向け表示名。
    private func transportName(_ kind: TransportEndpoint.Kind) -> String {
        switch kind {
        case .bluetoothLE: "Bluetooth LE"
        case .bluetoothClassic: "Bluetooth Classic / MFi"
        case .usbSerial: "USB"
        case .tcp: "ネットワーク"
        }
    }
}
#endif
