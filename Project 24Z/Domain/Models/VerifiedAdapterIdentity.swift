/// 承認済みAdapter単体transcriptと一致した、非機密の識別結果です。
nonisolated struct VerifiedAdapterIdentity: Equatable, Sendable {
    /// 利用者へ表示できるAdapter製品名です。
    let displayName: String

    /// Adapter hardwareが返した識別文字列です。
    let hardwareVersion: String

    /// Adapter firmwareが返した識別文字列です。
    let firmwareVersion: String
}
