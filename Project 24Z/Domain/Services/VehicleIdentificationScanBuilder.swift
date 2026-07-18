import Foundation

/// 一接続内のattemptを直列化し、業務用終端Evidenceを一件だけ作ります。
nonisolated struct VehicleIdentificationScanBuilder: Sendable {
    /// staleまたは終端後操作の拒否理由です。
    enum Error: Swift.Error, Equatable, Sendable {
        case staleGeneration
        case staleAttempt
        case alreadyFinalized
    }

    /// 接続Generationです。
    let connectionGeneration: ConnectionGeneration
    /// OBD接続UUIDです。
    let obdConnectionID: UUID
    private(set) var currentAttemptID: UUID
    private(set) var attemptIDs: [UUID]
    private var candidates: [VehicleIdentifierCandidate] = []
    private var isFinalized = false

    /// 新接続に最初のattemptを作ります。
    /// - Parameters:
    ///   - connectionGeneration: 新しい接続Generation。
    ///   - obdConnectionID: 新しい接続UUID。
    ///   - firstAttemptID: 最初のattempt UUID。
    init(
        connectionGeneration: ConnectionGeneration,
        obdConnectionID: UUID,
        firstAttemptID: UUID = UUID()
    ) {
        self.connectionGeneration = connectionGeneration
        self.obdConnectionID = obdConnectionID
        currentAttemptID = firstAttemptID
        attemptIDs = [firstAttemptID]
    }

    /// 同じ接続内で新attemptへ進みます。
    /// - Parameters:
    ///   - generation: callback側Generation。
    ///   - attemptID: 新しいattempt UUID。
    /// - Throws: stale Generationまたは終端後なら拒否します。
    mutating func beginRetry(generation: ConnectionGeneration, attemptID: UUID = UUID()) throws {
        guard !isFinalized else { throw Error.alreadyFinalized }
        guard generation == connectionGeneration else { throw Error.staleGeneration }
        currentAttemptID = attemptID
        attemptIDs.append(attemptID)
    }

    /// current generation＋attemptの候補だけを受理します。
    /// - Parameters:
    ///   - candidate: Raw保持候補。
    ///   - generation: responseのGeneration。
    ///   - attemptID: responseのattempt UUID。
    /// - Throws: stale tokenまたは終端後なら拒否します。
    mutating func accept(
        _ candidate: VehicleIdentifierCandidate,
        generation: ConnectionGeneration,
        attemptID: UUID
    ) throws {
        guard !isFinalized else { throw Error.alreadyFinalized }
        guard generation == connectionGeneration else { throw Error.staleGeneration }
        guard attemptID == currentAttemptID else { throw Error.staleAttempt }
        candidates.append(candidate)
    }

    /// builderを一度だけ終端し、接続全体のEvidence一件を返します。
    /// - Parameters:
    ///   - generation: 終端対象Generation。
    ///   - attemptID: 終端対象attempt UUID。
    ///   - finishedAt: 終端時刻。
    ///   - isComplete: 要求系列を完遂したかどうか。
    /// - Returns: DBへ渡す前の一件の終端Evidence。
    /// - Throws: stale tokenまたは二重終端なら拒否します。
    mutating func finalize(
        generation: ConnectionGeneration,
        attemptID: UUID,
        finishedAt: Date,
        isComplete: Bool
    ) throws -> VehicleScanTerminalEvidence {
        guard !isFinalized else { throw Error.alreadyFinalized }
        guard generation == connectionGeneration else { throw Error.staleGeneration }
        guard attemptID == currentAttemptID else { throw Error.staleAttempt }
        isFinalized = true
        return VehicleScanTerminalEvidence(
            scanID: UUID(),
            obdConnectionID: obdConnectionID,
            connectionGeneration: connectionGeneration,
            finalAttemptID: currentAttemptID,
            attemptIDs: attemptIDs,
            candidates: candidates,
            finishedAt: finishedAt,
            isComplete: isComplete
        )
    }
}
