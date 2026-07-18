/// Version付きValidation境界が返す候補判定です。
nonisolated struct VehicleIdentifierValidationResult: Equatable, Sendable {
    /// 候補の昇格可否です。
    enum Status: Equatable, Sendable {
        /// 承認済み規則の全検査を通過しました。
        case valid(normalizedValue: String)
        /// 承認済み規則で不合格です。
        case invalid
        /// 規則Hard Gateが未達のため判定を開始できません。
        case blocked
        /// 候補値がありません。
        case unavailable
    }

    /// 元のRaw候補です。
    let candidate: VehicleIdentifierCandidate
    /// Validation bundle Versionです。未確定ならnilです。
    let normalizationVersion: String?
    /// 判定です。
    let status: Status
}
