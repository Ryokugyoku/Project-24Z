/// Raw monitor開始に必要な証拠状態だけを表し、command bytesを公開しません。
nonisolated struct RawCANListenConfiguration: Equatable, Sendable {
    /// App API上の受信専用以外に確立した安全証拠です。
    enum SafetyEvidence: Equatable, Sendable { case unknown; case adapterModeVerified; case hardwareListenOnlyVerified }

    let safetyEvidence: SafetyEvidence
}
