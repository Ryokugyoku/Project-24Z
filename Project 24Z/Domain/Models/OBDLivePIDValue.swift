import Foundation

/// 一回の標準OBD読取で実応答からDecodeできたPID値です。
nonisolated struct OBDLivePIDValue: Equatable, Sendable, Identifiable {
    /// Service 01のPID codeを安定IDとして公開します。
    var id: UInt8 { parameter }

    /// Service 01のPID codeです。
    let parameter: UInt8

    /// 利用者向けの標準信号名です。
    let displayName: String

    /// 標準式でDecodeした数値です。
    let value: Double

    /// 数値に対応する単位です。
    let unit: String

    /// Decode根拠となった完全なAdapter応答です。
    let rawResponse: Data

    /// 応答を受理した時刻です。
    let observedAt: Date

    /// Platformが追加の業務判断なしに表示できる値です。
    var formattedValue: String {
        switch parameter {
        case 0x04:
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
}
