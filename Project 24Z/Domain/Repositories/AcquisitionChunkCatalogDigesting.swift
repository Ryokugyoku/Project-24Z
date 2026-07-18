import Foundation

/// Chunk目録のcanonical表現をfile digestと別にDigest化する能力です。
protocol AcquisitionChunkCatalogDigesting {
    /// file digestを含む目録値から独立したcanonical SHA-256を返します。
    func digest(for entry: AcquisitionChunkCatalogEntry) throws -> Data
}
