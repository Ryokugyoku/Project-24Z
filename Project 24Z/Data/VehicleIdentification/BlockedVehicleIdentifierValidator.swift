/// 識別規則Hard Gate未達時に全候補のProduction昇格を停止します。
nonisolated struct BlockedVehicleIdentifierValidator: VehicleIdentifierValidating {
    /// 候補Rawを保持し、valid Identifierへ昇格させません。
    /// - Parameter candidate: 保持対象候補。
    /// - Returns: Version未確定のblocked結果。
    func validate(_ candidate: VehicleIdentifierCandidate) -> VehicleIdentifierValidationResult {
        VehicleIdentifierValidationResult(
            candidate: candidate,
            normalizationVersion: nil,
            status: candidate.decodedCandidate == nil ? .unavailable : .blocked
        )
    }
}
