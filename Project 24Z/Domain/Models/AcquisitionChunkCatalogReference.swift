import Foundation

/// 起動時のDBとfile双方向照合に必要な最小目録参照です。
struct AcquisitionChunkCatalogReference: Equatable, Sendable {
    let chunkID: UUID
    let sessionID: UUID
    let relativePath: String
    let isAvailable: Bool
}
