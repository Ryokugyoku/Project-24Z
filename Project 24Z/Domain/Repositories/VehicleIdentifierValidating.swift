/// VIN／国内車台番号をVersion付き一次根拠だけでValidationする境界です。
nonisolated protocol VehicleIdentifierValidating: Sendable {
    /// Raw候補を保持したまま、承認済み規則がある場合だけvalidへ昇格します。
    /// - Parameter candidate: Decoderが明示した候補。
    /// - Returns: VersionとRaw候補を保持する判定。
    func validate(_ candidate: VehicleIdentifierCandidate) -> VehicleIdentifierValidationResult
}
