import Foundation

/// 停止境界の呼出し順序を記録するテスト専用Recorderです。
final class AcquisitionStopEventRecorder: @unchecked Sendable {
    /// 記録済みEventです。
    private(set) var events: [String] = []

    /// 一つのEventを末尾へ追加します。
    /// - Parameter event: 安定したテスト用Event名。
    func append(_ event: String) { events.append(event) }
}
