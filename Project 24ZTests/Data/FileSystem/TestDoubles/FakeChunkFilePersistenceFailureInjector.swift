import Foundation
@testable import Project_24Z

/// 指定段階だけを失敗させるfile persistence Fakeです。
struct FakeChunkFilePersistenceFailureInjector: ChunkFilePersistenceFailureInjecting {
    let failingFaults: Set<ChunkFilePersistenceFault>

    /// 指定段階なら部分書込エラーを送出します。
    /// - Parameter fault: 現在段階。
    func check(_ fault: ChunkFilePersistenceFault) throws {
        if failingFaults.contains(fault) { throw AcquisitionPersistenceError.partialWrite }
    }
}
