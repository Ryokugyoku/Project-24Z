import Foundation

/// PID／Raw CAN Hard Gate未達時に取得開始を拒否します。
struct UnavailablePreparedAcquisitionActivator: PreparedAcquisitionActivating {
    /// PID RequestやRaw monitorを開始しません。
    /// - Parameters:
    ///   - sessionID: 使用しないSession ID。
    ///   - primary: 使用しないPrimary。
    ///   - secondary: 使用しないSecondary。
    /// - Throws: 常に`acquisitionFailedAfterCommit`。
    func activate(sessionID: UUID, primary: PreparedAdapterConnection, secondary: PreparedAdapterConnection?) async throws {
        throw AcquisitionStartFailure.acquisitionFailedAfterCommit
    }
}
