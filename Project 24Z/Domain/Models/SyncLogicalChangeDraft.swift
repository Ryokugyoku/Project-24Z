import Foundation

/// Fake codecまたは将来の承認済みcodecが作るOrigin Change入力です。
struct SyncLogicalChangeDraft: Equatable, Sendable {
    /// Origin streamの閉じた分類です。
    enum StreamKind: String, Sendable { case vehicleDisplayName = "vehicle_display_name", vehicleLifecycle = "vehicle_lifecycle", immutableIdentity = "immutable_identity", sessionLog = "session_log" }
    /// Logical Changeの操作分類です。
    enum OperationKind: String, Sendable { case upsertImmutable = "upsert_immutable", upsertFieldRevision = "upsert_field_revision" }

    let logicalChangeID: UUID
    let originDeviceIdentityID: UUID
    let originSigningKeyVersion: Int
    let originSigningPublicKey: Data
    let originSigningKeyFingerprint: Data
    let originChangeID: UUID
    let streamKind: StreamKind
    let entityKind: String
    let entityID: UUID
    let originVehicleID: UUID?
    let originParentEntityKind: String?
    let originParentEntityID: UUID?
    let originSecondaryParentEntityKind: String?
    let originSecondaryParentEntityID: UUID?
    let originTertiaryParentEntityKind: String?
    let originTertiaryParentEntityID: UUID?
    let entitySchemaVersion: Int
    let operationKind: OperationKind
    let baseRevision: Int?
    let resultRevision: Int
    let contentDigest: Data
    let originEnvelopeCiphertext: Data
    let originSignature: Data
    let originMembershipProofDigest: Data
    let originCreatedAt: Date
    let createdByDeviceID: UUID

    /// Origin Changeの不変入力を作ります。
    init(logicalChangeID: UUID, originDeviceIdentityID: UUID, originSigningKeyVersion: Int, originSigningPublicKey: Data, originSigningKeyFingerprint: Data, originChangeID: UUID, streamKind: StreamKind, entityKind: String, entityID: UUID, originVehicleID: UUID?, originParentEntityKind: String?, originParentEntityID: UUID?, originSecondaryParentEntityKind: String? = nil, originSecondaryParentEntityID: UUID? = nil, originTertiaryParentEntityKind: String? = nil, originTertiaryParentEntityID: UUID? = nil, entitySchemaVersion: Int, operationKind: OperationKind, baseRevision: Int?, resultRevision: Int, contentDigest: Data, originEnvelopeCiphertext: Data, originSignature: Data, originMembershipProofDigest: Data, originCreatedAt: Date, createdByDeviceID: UUID) {
        self.logicalChangeID=logicalChangeID; self.originDeviceIdentityID=originDeviceIdentityID; self.originSigningKeyVersion=originSigningKeyVersion; self.originSigningPublicKey=originSigningPublicKey; self.originSigningKeyFingerprint=originSigningKeyFingerprint; self.originChangeID=originChangeID; self.streamKind=streamKind; self.entityKind=entityKind; self.entityID=entityID; self.originVehicleID=originVehicleID; self.originParentEntityKind=originParentEntityKind; self.originParentEntityID=originParentEntityID; self.originSecondaryParentEntityKind=originSecondaryParentEntityKind; self.originSecondaryParentEntityID=originSecondaryParentEntityID; self.originTertiaryParentEntityKind=originTertiaryParentEntityKind; self.originTertiaryParentEntityID=originTertiaryParentEntityID; self.entitySchemaVersion=entitySchemaVersion; self.operationKind=operationKind; self.baseRevision=baseRevision; self.resultRevision=resultRevision; self.contentDigest=contentDigest; self.originEnvelopeCiphertext=originEnvelopeCiphertext; self.originSignature=originSignature; self.originMembershipProofDigest=originMembershipProofDigest; self.originCreatedAt=originCreatedAt; self.createdByDeviceID=createdByDeviceID
    }
}
