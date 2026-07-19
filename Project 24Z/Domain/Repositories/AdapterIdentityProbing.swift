/// 車両busへRequestを送らず、承認済みUSB Adapter単体識別だけを行う能力です。
nonisolated protocol AdapterIdentityProbing: Sendable {
    /// 対象Descriptorに完全一致する単一Endpointを開き、固定transcriptを各一回だけ照合します。
    /// - Returns: transcriptと一致した非機密Adapter identity。
    /// - Throws: Endpoint不一致、複数候補、timeout、切断、想定外応答。
    func verifyApprovedAdapter() async throws -> VerifiedAdapterIdentity

    /// 進行中Requestを取り消し、応答を待たずTransport closeを要求します。
    func cancel() async
}
