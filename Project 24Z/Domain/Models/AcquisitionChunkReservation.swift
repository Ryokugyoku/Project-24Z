import Foundation

/// DBで消費済みにした不変Chunk識別子とSequence範囲です。
struct AcquisitionChunkReservation: Equatable, Sendable {
    let chunkID: UUID
    let sessionID: UUID
    let streamID: UUID
    let chunkSequence: Int64
    let firstRecordSequence: Int64
    let lastRecordSequence: Int64
}
