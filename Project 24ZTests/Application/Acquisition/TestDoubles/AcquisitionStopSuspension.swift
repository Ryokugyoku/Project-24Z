import Foundation

/// 並行停止テストで最初の停止処理を決定的に待機させる境界です。
actor AcquisitionStopSuspension {
    /// 待機中のcontinuationです。
    private var continuation: CheckedContinuation<Void, Never>?

    /// 最初の停止処理が待機地点へ到達したかを示します。
    private var isSuspended = false

    /// resumeされるまで呼出し元を待機させます。
    func suspend() async {
        await withCheckedContinuation { continuation in
            isSuspended = true
            self.continuation = continuation
        }
    }

    /// 最初の停止処理が待機地点へ到達するまで待ちます。
    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    /// 待機中の停止処理を一度だけ再開します。
    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
