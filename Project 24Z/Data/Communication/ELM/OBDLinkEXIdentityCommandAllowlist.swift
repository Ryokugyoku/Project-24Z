import Foundation

/// 2026-07-19のAdapter単体transcriptで固定したOBDLink EX identity allowlistです。
nonisolated enum OBDLinkEXIdentityCommandAllowlist {
    /// EX101／STN2232 v5.10.3のAdapter単体識別だけを許可するVersion 1 allowlistです。
    static let version1 = VersionedELMCommandAllowlist(
        version: 1,
        adapterModel: "OBDLink EX EX101",
        firmwareVersion: "STN2232 v5.10.3",
        mode: "adapter_identity_only",
        adapterResetTranscriptVerified: true,
        entries: [
            .init(request: .adapterInputBoundaryClear, bytes: Data("??\r".utf8)),
            .init(request: .adapterInitializationReset, bytes: Data("ATZ\r".utf8)),
            .init(request: .adapterHardwareIdentification, bytes: Data("STDI\r".utf8)),
            .init(request: .adapterFirmwareIdentification, bytes: Data("STI\r".utf8)),
        ]
    )
}
