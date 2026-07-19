import Combine
import Foundation

/// HOMEへ公開する、最後の実OBD probeで値取得に成功したPID Snapshotです。
@MainActor
final class VehicleTelemetryModel: ObservableObject {
    /// 値取得成功PIDだけをPID code順で公開します。
    @Published private(set) var successfulPIDValues: [OBDLivePIDValue] = []

    /// 現在値が実応答由来かを説明する非機密状態です。
    @Published private(set) var statusMessage = "実車から取得できたPID値はまだありません。"

    /// 実OBD Discovery結果を一括置換します。
    /// - Parameter snapshot: VIN確定まで完遂した一接続Snapshot。
    func apply(_ snapshot: OBDVehicleDiscoverySnapshot) {
        successfulPIDValues = snapshot.successfulPIDValues.sorted { $0.parameter < $1.parameter }
        statusMessage = successfulPIDValues.isEmpty
            ? "車両識別は完了しましたが、値取得まで成功した対象PIDはありませんでした。"
            : "最後の実車接続で値取得まで成功したPIDです。継続的なlive値ではありません。"
    }

    /// 接続失敗時に直前の成功値をliveと誤認させない説明へ更新します。
    func markStale() {
        guard !successfulPIDValues.isEmpty else { return }
        statusMessage = "前回の実車接続で取得した値です。現在接続中のlive値ではありません。"
    }
}
