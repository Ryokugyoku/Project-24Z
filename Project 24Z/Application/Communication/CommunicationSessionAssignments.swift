import Foundation

/// 一Session内で不変のPrimary／Secondary割当を調停します。
nonisolated struct CommunicationSessionAssignments: Equatable, Sendable {
    let sessionID: UUID
    let primary: AdapterReference?
    let secondary: AdapterReference?

    /// 役割と物理Adapter重複を検証して割当を作ります。
    /// - Parameters:
    ///   - sessionID: 明示開始した取得Session。
    ///   - primary: OBD専用Adapter。OBD未使用時は`nil`。
    ///   - secondary: Raw CAN専用Adapter。Raw未使用時は`nil`。
    ///   - identitiesAreDistinct: 両方指定時に別物理Adapterと確認済みか。
    /// - Throws: 同一またはIdentity不明の場合。
    init(sessionID: UUID, primary: AdapterReference?, secondary: AdapterReference?, identitiesAreDistinct: Bool?) throws {
        if let primary, let secondary {
            guard primary != secondary else { throw CommunicationRuntimeError.adapterAlreadyAssigned }
            guard let identitiesAreDistinct else { throw CommunicationRuntimeError.adapterIdentityUnknown }
            guard identitiesAreDistinct else { throw CommunicationRuntimeError.adapterAlreadyAssigned }
        }
        self.sessionID = sessionID
        self.primary = primary
        self.secondary = secondary
    }

    /// Session内でのroleまたはAdapter交換を拒否します。
    /// - Parameters:
    ///   - primary: 変更後Primary候補。
    ///   - secondary: 変更後Secondary候補。
    /// - Throws: 初期割当と異なる場合は常に新Session要求。
    func validateUnchanged(primary: AdapterReference?, secondary: AdapterReference?) throws {
        guard self.primary == primary, self.secondary == secondary else {
            throw CommunicationRuntimeError.roleChangeRequiresNewSession
        }
    }
}
