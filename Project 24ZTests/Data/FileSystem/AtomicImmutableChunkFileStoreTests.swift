import Foundation
import Testing
@testable import Project_24Z

/// immutable fileの確定、失敗注入、再起動隔離、容量不足を検証します。
@MainActor
struct AtomicImmutableChunkFileStoreTests {
    /// 未知・malformed相当の任意bytesも推測変換せず完全一致で保存します。
    @Test
    func preservesOpaqueUnknownAndMalformedBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data([0x00, 0xff, 0x7f, 0x13, 0x00])
        let store = AtomicImmutableChunkFileStore(rootURL: fixture.root, requiredSafetyMargin: 0)

        let finalized = try store.finalize(fixture.chunk(bytes: bytes))

        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(finalized.relativePath)) == bytes)
        #expect(finalized.ciphertextDigest.count == 32)
    }

    /// staging同期前の部分失敗を正常Chunkにせず、再起動時も削除せず隔離します。
    @Test
    func partialWriteRemainsRecoverableAndIsQuarantinedOnRestart() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let failing = AtomicImmutableChunkFileStore(
            rootURL: fixture.root,
            capacityProvider: FakeChunkStorageCapacityProvider(capacity: 1_000_000),
            failureInjector: FakeChunkFilePersistenceFailureInjector(failingFaults: [.afterStagingWrite]),
            requiredSafetyMargin: 0
        )
        #expect(throws: AcquisitionPersistenceError.partialWrite) {
            try failing.finalize(fixture.chunk(bytes: Data([1, 2, 3])))
        }

        let restarted = AtomicImmutableChunkFileStore(rootURL: fixture.root, requiredSafetyMargin: 0)
        let isolated = try restarted.quarantineStagingFiles()
        #expect(isolated.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(isolated[0]).path))
        let chunkSubpaths = try FileManager.default.subpathsOfDirectory(atPath: fixture.root.appendingPathComponent("chunks").path)
        #expect(!chunkSubpaths.contains(where: { $0.hasSuffix(".p24zc") }))
    }

    /// rename後の失敗はfileを削除せず孤立fileとして残し、ACK相当を返しません。
    @Test
    func failureAfterRenameLeavesOrphanForCatalogRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = AtomicImmutableChunkFileStore(
            rootURL: fixture.root,
            capacityProvider: FakeChunkStorageCapacityProvider(capacity: 1_000_000),
            failureInjector: FakeChunkFilePersistenceFailureInjector(failingFaults: [.afterRename]),
            requiredSafetyMargin: 0
        )
        #expect(throws: AcquisitionPersistenceError.partialWrite) {
            try store.finalize(fixture.chunk(bytes: Data([4, 5, 6])))
        }
        let files = try FileManager.default.subpathsOfDirectory(atPath: fixture.root.appendingPathComponent("chunks").path)
        #expect(files.contains(where: { $0.hasSuffix(".p24zc") }))
    }

    /// Critical容量不足では既存fileを消さず新規stagingも作りません。
    @Test
    func capacityCriticalDoesNotDeleteExistingData() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let existing = fixture.root.appendingPathComponent("existing.keep")
        let existingData = Data([9, 9])
        try existingData.write(to: existing)
        let store = AtomicImmutableChunkFileStore(
            rootURL: fixture.root,
            capacityProvider: FakeChunkStorageCapacityProvider(capacity: 0),
            requiredSafetyMargin: 0
        )

        #expect(throws: AcquisitionPersistenceError.storageCapacityCritical) {
            try store.finalize(fixture.chunk(bytes: Data([1])))
        }
        #expect(try Data(contentsOf: existing) == existingData)
        let staging = fixture.root.appendingPathComponent("staging")
        #expect(try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).isEmpty)
    }

    /// 一テスト専用のChunk rootと入力を所有します。
    private struct Fixture {
        let root: URL
        let sessionID = UUID()
        let streamID = UUID()
        let chunkID = UUID()
        let epochID = UUID()

        /// UUID名の一時rootを作成します。
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("p24z-chunk-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        /// 任意bytesを持つ準備済みFake Chunkを返します。
        func chunk(bytes: Data) -> PreparedAcquisitionChunk {
            PreparedAcquisitionChunk(reservation: .init(chunkID: chunkID,sessionID: sessionID,streamID: streamID,chunkSequence: 0,firstRecordSequence: 0,lastRecordSequence: 0),clockEpochID: epochID,firstMonotonicNanoseconds: 1,lastMonotonicNanoseconds: 1,plaintextSize: Int64(bytes.count),compressedSize: Int64(bytes.count),recordFormatVersion: 1,compressionFormatVersion: 1,encryptionFormatVersion: 1,keyVersion: 1,bytes: bytes)
        }

        /// このfixtureだけを削除します。
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
