/// 取得開始境界の呼出し順序を記録します。
final class AcquisitionStartEventRecorder: @unchecked Sendable {
    /// 記録済みEventです。
    private(set) var events: [String] = []

    /// Eventを末尾へ追加します。
    /// - Parameter event: 安定したテスト用Event名。
    func append(_ event: String) { events.append(event) }
}
