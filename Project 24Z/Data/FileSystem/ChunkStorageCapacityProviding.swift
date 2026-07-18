import Foundation

/// Chunk rootと同じVolumeの利用可能容量を取得します。
protocol ChunkStorageCapacityProviding: Sendable {
    /// - Parameter url: 保存先Volume上のURL。
    /// - Returns: 重要用途に利用可能なbyte数。不明ならnil。
    func availableCapacity(at url: URL) throws -> Int64?
}

/// Foundation resource valueから容量を読むProduction実装です。
struct FileSystemChunkStorageCapacityProvider: ChunkStorageCapacityProviding {
    /// 容量Providerを構成します。
    init() {}

    /// Volumeの重要用途向け空き容量を返します。
    /// - Parameter url: 保存先URL。
    /// - Returns: 利用可能byte数。不明ならnil。
    func availableCapacity(at url: URL) throws -> Int64? {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage
    }
}
