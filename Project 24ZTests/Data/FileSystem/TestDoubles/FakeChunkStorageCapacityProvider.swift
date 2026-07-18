import Foundation
@testable import Project_24Z

/// 容量不足を決定的に再現する容量Providerです。
struct FakeChunkStorageCapacityProvider: ChunkStorageCapacityProviding {
    let capacity: Int64?

    /// 固定容量を返します。
    /// - Parameter url: 使用しない保存先。
    /// - Returns: 注入した容量。
    func availableCapacity(at url: URL) throws -> Int64? { capacity }
}
