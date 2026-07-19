#if os(iOS)
import SwiftUI

/// iOS専用の接続しないEndpoint候補選択sheetです。
struct IOSConnectionCandidateSelectionView: View {
    /// 親画面と同じApplication Modelです。
    @ObservedObject var model: ConnectionSettingsModel

    /// 候補の非機密情報と確定Actionだけを表示します。
    var body: some View {
        NavigationStack {
            List {
                if let message = model.state.discoveryMessage { Text(message) }
                ForEach(model.state.discoveredCandidates, id: \.endpointDigest) { candidate in
                    VStack(alignment: .leading) {
                        Text(candidate.displayName)
                        Text(candidate.transportKind == .bluetoothLE ? "Bluetooth LE" : "Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("このデバイスを使用") {
                            guard let role = model.state.selectingRole else { return }
                            Task { await model.perform(.selectCandidate(candidate, role: role)) }
                        }
                    }
                }
            }
            .navigationTitle("デバイスを選択")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { Task { await model.perform(.cancelDiscovery) } }
                }
            }
        }
    }
}
#endif
