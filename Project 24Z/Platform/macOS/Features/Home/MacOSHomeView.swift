#if os(macOS)
import SwiftUI

/// macOSのホーム画面を表示します。
struct MacOSHomeView: View {
    /// Composition Rootから注入されたダッシュボードModelです。
    @EnvironmentObject private var model: DashboardModel

    /// 最後の実OBD probeで値取得に成功したPID Snapshotです。
    @EnvironmentObject private var telemetryModel: VehicleTelemetryModel

    /// Primary未設定時に設定画面へ移動するPlatform Navigation Actionです。
    let openConnectionSettings: () -> Void

    /// macOS専用ダッシュボードを表示します。
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("ログ収集") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.state.statusMessage)
                    Button(model.state.primaryAction.title) {
                        performPrimaryAction(model.state.primaryAction.action)
                    }
                    .disabled(!model.state.primaryAction.isEnabled)
                    .accessibilityLabel(model.state.primaryAction.accessibilityLabel)
                    .accessibilityHint(model.state.primaryAction.accessibilityHint)

                    if case .awaitingPIDOnlyConfirmation = model.state.acquisitionState {
                        HStack {
                            Button("PIDのみで開始") { Task { await model.confirmPIDOnlyStart() } }
                            Button("キャンセル", role: .cancel) { Task { await model.cancelStart() } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            GroupBox("取得成功PID") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(telemetryModel.statusMessage)
                        .foregroundStyle(.secondary)
                    if telemetryModel.successfulPIDValues.isEmpty {
                        ContentUnavailableView("PID値なし", systemImage: "waveform.path.ecg")
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("PID").fontWeight(.semibold)
                                Text("信号").fontWeight(.semibold)
                                Text("値").fontWeight(.semibold)
                            }
                            ForEach(telemetryModel.successfulPIDValues) { reading in
                                GridRow {
                                    Text(String(format: "01 %02X", reading.parameter))
                                        .monospacedDigit()
                                    Text(reading.displayName)
                                    Text("\(reading.formattedValue) \(reading.unit)")
                                        .monospacedDigit()
                                }
                            }
                        }
                        .accessibilityIdentifier("project24z.home.successfulPIDs")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            Spacer()
        }
        .padding(24)
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
