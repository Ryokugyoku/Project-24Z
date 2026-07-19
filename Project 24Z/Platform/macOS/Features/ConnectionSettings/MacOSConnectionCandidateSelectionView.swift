#if os(macOS)
import SwiftUI

/// macOS専用の接続しないEndpoint候補選択sheetです。
struct MacOSConnectionCandidateSelectionView: View {
    /// 親画面と同じApplication Modelです。
    @ObservedObject var model: ConnectionSettingsModel

    /// 候補の非機密情報と確定Actionだけを表示します。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("デバイスを選択").font(.title2)
            if let message = model.state.discoveryMessage { Text(message) }
            List(model.state.discoveredCandidates, id: \.endpointDigest) { candidate in
                HStack {
                    VStack(alignment: .leading) {
                        Text(candidate.displayName)
                        Text(candidate.transportKind == .usbSerial ? "USB" : "Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("このデバイスを使用") {
                        guard let role = model.state.selectingRole else { return }
                        Task { await model.perform(.selectCandidate(candidate, role: role)) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("キャンセル") { Task { await model.perform(.cancelDiscovery) } }
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}
#endif
