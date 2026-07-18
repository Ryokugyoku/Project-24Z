import Foundation
import Testing
@testable import Project_24Z

/// Durable ACKとRepository commit失敗後の孤立file保持を検証します。
@MainActor
struct PersistAcquisitionChunkUseCaseTests {
    /// file確定後にRepositoryが失敗した場合はACKせず、fileを削除しません。
    @Test
    func repositoryFailureLeavesOrphanAndDoesNotAcknowledge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("p24z-ack-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileStore = AtomicImmutableChunkFileStore(
            rootURL: root,
            capacityProvider: FakeChunkStorageCapacityProvider(capacity: 1_000_000),
            requiredSafetyMargin: 0
        )
        let repository = FailingCommitAcquisitionRepository()
        let useCase = PersistAcquisitionChunkUseCase(fileStore: fileStore,repository: repository,catalogDigester: SHA256AcquisitionChunkCatalogDigester())
        let sessionID = UUID(), streamID = UUID()
        let chunk = PreparedAcquisitionChunk(reservation: .init(chunkID: UUID(),sessionID: sessionID,streamID: streamID,chunkSequence: 0,firstRecordSequence: 0,lastRecordSequence: 0),clockEpochID: UUID(),firstMonotonicNanoseconds: 1,lastMonotonicNanoseconds: 1,plaintextSize: 3,compressedSize: 3,recordFormatVersion: 1,compressionFormatVersion: 1,encryptionFormatVersion: 1,keyVersion: 1,bytes: Data([0xde,0xad,0xbe]))

        #expect(throws: AcquisitionPersistenceError.catalogCommitFailed) {
            try useCase.execute(chunk: chunk, createdAt: Date())
        }
        #expect(try fileStore.finalizedRelativePaths().count == 1)
    }

    /// commitだけを失敗させるRepository Fakeです。
    private final class FailingCommitAcquisitionRepository: AcquisitionRepository {
        /// 使用しない開始処理です。
        func start(session: AcquisitionSession, streams: [AcquisitionStream], epoch: AcquisitionClockEpoch) throws {}
        /// 使用しない予約処理です。
        func reserveChunk(streamID: UUID, recordCount: Int64, expectedStreamRevision: Int, updatedAt: Date) throws -> AcquisitionChunkReservation { throw AcquisitionPersistenceError.unavailable }
        /// file確定後のcatalog commitを失敗させます。
        func commitChunk(_ entry: AcquisitionChunkCatalogEntry) throws -> AcquisitionChunkCatalogEntry { throw AcquisitionPersistenceError.catalogCommitFailed }
        /// 使用しないGap処理です。
        func recordGap(_ gap: AcquisitionGap) throws {}
        /// 使用しないbinding処理です。
        func bind(sessionID: UUID, vehicleID: UUID, expectedSessionRevision: Int, expectedVehicleLifecycleRevision: Int) throws {}
        /// 使用しないSession終端です。
        func finishSession(sessionID: UUID, expectedSessionRevision: Int, reason: AcquisitionSession.EndReason, endedAt: Date, deviceID: UUID) throws {}
        /// 使用しないSession復旧です。
        func recoverInterruptedSessions(at recoveredAt: Date, deviceID: UUID) throws -> [UUID] { [] }
        /// 使用しない目録参照です。
        func chunkCatalogReferences() throws -> [AcquisitionChunkCatalogReference] { [] }
        /// 使用しないmissing処理です。
        func markChunkMissing(_ reference: AcquisitionChunkCatalogReference, detectedAt: Date) throws {}
        /// 使用しないFinding処理です。
        func recordUncatalogedFinding(kind: StorageIntegrityFindingKind, observedPath: String, quarantinePath: String, detectedAt: Date) throws {}
    }
}
