import CryptoKit
import Darwin
import Foundation

/// 同一Volumeのstagingからatomic renameするimmutable Chunk file Adapterです。
final class AtomicImmutableChunkFileStore: ImmutableChunkFileStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let capacityProvider: any ChunkStorageCapacityProviding
    private let failureInjector: any ChunkFilePersistenceFailureInjecting
    private let requiredSafetyMargin: Int64

    /// scope専用rootと注入可能な保全依存を受け取ります。
    /// - Parameters:
    ///   - rootURL: 不透明scope-local-id配下のroot。
    ///   - fileManager: ファイル操作境界。
    ///   - capacityProvider: 同じVolumeの容量取得境界。
    ///   - failureInjector: 保存段階の失敗注入境界。
    ///   - requiredSafetyMargin: 入力サイズに追加して必要な空きbyte数。
    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        capacityProvider: any ChunkStorageCapacityProviding = FileSystemChunkStorageCapacityProvider(),
        failureInjector: any ChunkFilePersistenceFailureInjecting = NoChunkFilePersistenceFailureInjector(),
        requiredSafetyMargin: Int64 = 1_048_576
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.capacityProvider = capacityProvider
        self.failureInjector = failureInjector
        self.requiredSafetyMargin = requiredSafetyMargin
    }

    /// staging fileを同期・読戻し後にrenameし、親directory同期と最終読戻しを行います。
    /// - Parameter chunk: 準備済みの不透明Chunk bytes。
    /// - Returns: 最終相対path、byte数、file digest。
    /// - Throws: 容量不足、部分書込、読戻し不一致、既存path競合時の安定エラー。
    func finalize(_ chunk: PreparedAcquisitionChunk) throws -> FinalizedChunkFile {
        try validate(chunk)
        try prepareDirectories(for: chunk)
        if let available = try capacityProvider.availableCapacity(at: rootURL),
           available < Int64(chunk.bytes.count) + requiredSafetyMargin {
            throw AcquisitionPersistenceError.storageCapacityCritical
        }

        let stagingURL = rootURL.appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString.lowercased()).partial")
        let relativePath = finalRelativePath(for: chunk)
        let finalURL = try resolvedURL(for: relativePath)
        guard !fileManager.fileExists(atPath: finalURL.path) else {
            throw AcquisitionPersistenceError.conflict
        }

        guard fileManager.createFile(atPath: stagingURL.path, contents: nil) else {
            throw AcquisitionPersistenceError.unavailable
        }
        do {
            let handle = try FileHandle(forWritingTo: stagingURL)
            do {
                try handle.write(contentsOf: chunk.bytes)
                try failureInjector.check(.afterStagingWrite)
                try handle.synchronize()
                try failureInjector.check(.afterStagingSynchronize)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let expectedDigest = Data(SHA256.hash(data: chunk.bytes))
            try verifyFile(at: stagingURL, expectedSize: chunk.bytes.count, expectedDigest: expectedDigest)
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            try failureInjector.check(.afterRename)
            try synchronizeDirectory(at: finalURL.deletingLastPathComponent())
            try failureInjector.check(.beforeFinalVerification)
            try verifyFile(at: finalURL, expectedSize: chunk.bytes.count, expectedDigest: expectedDigest)
            return FinalizedChunkFile(
                relativePath: relativePath,
                byteCount: Int64(chunk.bytes.count),
                ciphertextDigest: expectedDigest
            )
        } catch let error as AcquisitionPersistenceError {
            throw error
        } catch {
            throw AcquisitionPersistenceError.partialWrite
        }
    }

    /// staging残存物を自動削除せずquarantineへatomicに移します。
    /// - Returns: 隔離後のroot相対path一覧。
    /// - Throws: 列挙または移動に失敗した場合の利用不能エラー。
    func quarantineStagingFiles() throws -> [String] {
        let staging = rootURL.appendingPathComponent("staging", isDirectory: true)
        let quarantine = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        do {
            return try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isRegularFileKey])
                .map { source in
                    let name = "\(UUID().uuidString.lowercased())-\(source.lastPathComponent).isolated"
                    let destination = quarantine.appendingPathComponent(name)
                    try fileManager.moveItem(at: source, to: destination)
                    return "quarantine/\(name)"
                }
        } catch {
            throw AcquisitionPersistenceError.unavailable
        }
    }

    /// chunks配下の通常fileだけを列挙し、symbolic linkは正常候補に含めません。
    /// - Returns: root相対のChunk path一覧。
    /// - Throws: 列挙失敗時`unavailable`。
    func finalizedRelativePaths() throws -> [String] {
        let chunks = rootURL.appendingPathComponent("chunks", isDirectory: true)
        try fileManager.createDirectory(at: chunks, withIntermediateDirectories: true)
        guard let enumerator = fileManager.enumerator(
            at: chunks,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw AcquisitionPersistenceError.unavailable }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let prefix = rootURL.path + "/"
            guard url.standardizedFileURL.path.hasPrefix(prefix) else { continue }
            paths.append(String(url.standardizedFileURL.path.dropFirst(prefix.count)))
        }
        return paths.sorted()
    }

    /// 孤立fileを自動削除せず、元名と無関係なUUID名で隔離します。
    /// - Parameter relativePath: chunks配下で検出したroot相対path。
    /// - Returns: 隔離後のroot相対path。
    /// - Throws: path逸脱や移動失敗時の安定エラー。
    func quarantineFinalizedFile(relativePath: String) throws -> String {
        guard relativePath.hasPrefix("chunks/") else { throw AcquisitionPersistenceError.invalidRequest }
        let source = try resolvedURL(for: relativePath)
        let quarantine = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased())-\(UUID().uuidString.lowercased()).isolated"
        let destination = quarantine.appendingPathComponent(name)
        do {
            try fileManager.moveItem(at: source, to: destination)
            try synchronizeDirectory(at: quarantine)
            return "quarantine/\(name)"
        } catch let error as AcquisitionPersistenceError { throw error }
        catch { throw AcquisitionPersistenceError.unavailable }
    }

    /// 入力の範囲とformat値を検証します。
    /// - Parameter chunk: 検証するChunk。
    /// - Throws: 不正なら`invalidRequest`。
    private func validate(_ chunk: PreparedAcquisitionChunk) throws {
        let reservation = chunk.reservation
        guard !chunk.bytes.isEmpty,
              reservation.firstRecordSequence >= 0,
              reservation.lastRecordSequence >= reservation.firstRecordSequence,
              chunk.firstMonotonicNanoseconds >= 0,
              chunk.lastMonotonicNanoseconds >= chunk.firstMonotonicNanoseconds,
              chunk.plaintextSize >= 0,
              chunk.compressedSize >= 0,
              chunk.recordFormatVersion > 0,
              chunk.compressionFormatVersion > 0,
              chunk.encryptionFormatVersion > 0,
              chunk.keyVersion > 0 else {
            throw AcquisitionPersistenceError.invalidRequest
        }
    }

    /// staging、quarantine、最終親directoryを作成します。
    /// - Parameter chunk: 最終pathを決めるChunk。
    /// - Throws: directory作成失敗。
    private func prepareDirectories(for chunk: PreparedAcquisitionChunk) throws {
        for directory in [
            rootURL.appendingPathComponent("staging", isDirectory: true),
            rootURL.appendingPathComponent("quarantine", isDirectory: true),
            try resolvedURL(for: finalRelativePath(for: chunk)).deletingLastPathComponent(),
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// UUIDと固定幅Sequenceだけの最終相対pathを生成します。
    /// - Parameter chunk: 識別子を持つChunk。
    /// - Returns: root相対path。
    private func finalRelativePath(for chunk: PreparedAcquisitionChunk) -> String {
        let reservation = chunk.reservation
        let sequence = String(format: "%020lld", reservation.chunkSequence)
        return "chunks/\(reservation.sessionID.uuidString.lowercased())/\(reservation.streamID.uuidString.lowercased())/\(sequence)-\(reservation.chunkID.uuidString.lowercased()).p24zc"
    }

    /// root外へ解決されない正規相対pathだけをURL化します。
    /// - Parameter relativePath: 検証するpath。
    /// - Returns: root配下の標準化URL。
    /// - Throws: 絶対path、親参照、root逸脱時`invalidRequest`。
    private func resolvedURL(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == ".." }) else {
            throw AcquisitionPersistenceError.invalidRequest
        }
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path + "/") else {
            throw AcquisitionPersistenceError.invalidRequest
        }
        return candidate
    }

    /// file長とSHA-256を全読戻しで検証します。
    /// - Parameters:
    ///   - url: 検証対象。
    ///   - expectedSize: 期待byte数。
    ///   - expectedDigest: 期待SHA-256。
    /// - Throws: 不一致なら`verificationFailed`。
    private func verifyFile(at url: URL, expectedSize: Int, expectedDigest: Data) throws {
        let reread = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard reread.count == expectedSize,
              Data(SHA256.hash(data: reread)) == expectedDigest else {
            throw AcquisitionPersistenceError.verificationFailed
        }
    }

    /// renameを含むdirectory entryをfsync相当で永続化要求します。
    /// - Parameter url: 同期する親directory。
    /// - Throws: openまたはfsync失敗時`partialWrite`。
    private func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw AcquisitionPersistenceError.partialWrite }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw AcquisitionPersistenceError.partialWrite }
    }
}
