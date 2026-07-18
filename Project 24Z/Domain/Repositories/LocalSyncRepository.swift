import Foundation

/// Hard Gateに依存しないローカル同期台帳と状態機械の保存境界です。
protocol LocalSyncRepository {
    /// Origin／Stream末尾をtransaction内で読み、0始まりSequenceとChainを一件追記します。
    func appendLogicalChange(_ draft: SyncLogicalChangeDraft) throws -> PersistedSyncLogicalChange
    /// applied／duplicate Receiptまたはacked Deliveryを一件だけ越えてCursorを進めます。
    func advanceCursor(peerIdentityID: UUID, direction: String, originDeviceIdentityID: UUID, streamKind: SyncLogicalChangeDraft.StreamKind, updatedAt: Date, deviceID: UUID) throws
    /// 全Materialization検査済みのpreparing graphをreadyへ進めます。
    func markAliasReady(aliasID: UUID, readyAt: Date, deviceID: UUID) throws
    /// 旧activeをsuperseded、新readyをactiveへ一transactionで切り替えます。
    func publishAlias(aliasID: UUID, activatedAt: Date, deviceID: UUID) throws
    /// 全Chunkがcataloged済みのSession TransferへDurable ACKを確定します。
    func markSessionTransferDurable(transferID: UUID, acknowledgementID: UUID, durableAt: Date, deviceID: UUID) throws
}
