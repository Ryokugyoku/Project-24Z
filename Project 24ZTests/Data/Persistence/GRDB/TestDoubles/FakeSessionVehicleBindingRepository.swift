import Foundation
@testable import Project_24Z

/// Session bindingの別transaction、冪等成功、競合をテストするFakeです。
final class FakeSessionVehicleBindingRepository: SessionVehicleBindingRepository {
    /// Fake内の最小Session状態です。
    struct SessionState: Equatable {
        /// Session UUIDです。
        let sessionID: UUID
        /// 所属済み車両。未割当ならnilです。
        var vehicleID: UUID?
        /// 楽観ロックRevisionです。
        var revision: Int
        /// 保存確定後のbinding拒否に使います。
        var isFinalized: Bool
    }

    private var sessions: [UUID: SessionState] = [:]
    private let activeVehicleRevisions: [UUID: Int]

    /// active車両とLifecycle Revisionを受け取ります。
    /// - Parameter activeVehicleRevisions: binding可能な車両Revision台帳。
    init(activeVehicleRevisions: [UUID: Int]) {
        self.activeVehicleRevisions = activeVehicleRevisions
    }

    /// 未割当SessionをFakeへ追加します。
    /// - Parameter state: 初期Session状態。
    func seed(_ state: SessionState) {
        sessions[state.sessionID] = state
    }

    /// 現在のSession状態を返します。
    /// - Parameter sessionID: 取得するSession UUID。
    /// - Returns: 登録済み状態またはnil。
    func state(sessionID: UUID) -> SessionState? {
        sessions[sessionID]
    }

    /// 登録transactionとは独立してSessionだけを更新します。
    /// - Parameters:
    ///   - sessionID: 未割当Session UUID。
    ///   - vehicleID: active車両UUID。
    ///   - expectedSessionRevision: 期待Session Revision。
    ///   - expectedVehicleLifecycleRevision: 期待Lifecycle Revision。
    /// - Throws: finalized、別車両、Revision不一致、active根拠不一致で`conflict`。
    func bind(
        sessionID: UUID,
        vehicleID: UUID,
        expectedSessionRevision: Int,
        expectedVehicleLifecycleRevision: Int
    ) throws {
        guard var session = sessions[sessionID],
              activeVehicleRevisions[vehicleID] == expectedVehicleLifecycleRevision else {
            throw VehiclePersistenceError.conflict
        }
        if session.vehicleID == vehicleID {
            return
        }
        guard session.vehicleID == nil,
              !session.isFinalized,
              session.revision == expectedSessionRevision else {
            throw VehiclePersistenceError.conflict
        }
        session.vehicleID = vehicleID
        session.revision += 1
        sessions[sessionID] = session
    }
}
