import Foundation

/// PIDまたはRaw CANを独立に採番する取得Streamです。
struct AcquisitionStream: Equatable, Sendable {
    /// Streamの記録種別です。
    enum Kind: String, Sendable { case obdPID = "obd_pid"; case rawCAN = "raw_can" }
    /// Adapterの固定役割です。
    enum AdapterRole: String, Sendable { case primary; case secondary }
    /// Streamの取得状態です。
    enum State: String, Sendable { case active; case pauseRequested = "pause_requested"; case paused; case reconnecting; case stopRequested = "stop_requested"; case stopped; case interrupted }

    let streamID: UUID
    let sessionID: UUID
    let kind: Kind
    let adapterRole: AdapterRole
    let adapterReferenceID: String
    let connectionInstanceID: UUID
    let state: State
    let startedAt: Date
    let endedAt: Date?
    let nextRecordSequence: Int64
    let nextChunkSequence: Int64
    let revision: Int
    let updatedAt: Date
}
