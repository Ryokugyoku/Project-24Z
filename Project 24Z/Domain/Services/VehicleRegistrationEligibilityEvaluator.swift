/// Identifier Validationと重複候補を推測せず分類する純粋Domain規則です。
nonisolated struct VehicleRegistrationEligibilityEvaluator: Sendable {
    /// Validation済み候補とDigest照合結果を登録可否へ分類します。
    /// - Parameters:
    ///   - validations: Version付きValidation結果。
    ///   - matches: valid候補と同じ順序の既存車両照合結果。
    /// - Returns: blocked、新規、active／archived候補、Conflict。
    func evaluate(
        validations: [VehicleIdentifierValidationResult],
        matches: [VehicleIdentity?]
    ) -> VehicleRegistrationEligibility {
        let validValues = validations.compactMap { validation -> (VehicleIdentifierEvidence.Kind, String)? in
            guard case .valid(let normalizedValue) = validation.status else { return nil }
            return (validation.candidate.kind, normalizedValue)
        }
        guard !validValues.isEmpty else { return .blocked }
        guard validValues.count == matches.count else { return .conflict }

        var valuesByKind: [VehicleIdentifierEvidence.Kind: String] = [:]
        for (kind, value) in validValues {
            if let existing = valuesByKind[kind], existing != value { return .conflict }
            valuesByKind[kind] = value
        }
        let matchedVehicles = matches.compactMap { $0 }
        let matchedIDs = Set(matchedVehicles.map(\.vehicleID))
        guard matchedIDs.count <= 1 else { return .conflict }
        guard matchedVehicles.isEmpty || matchedVehicles.count == matches.count else { return .conflict }
        guard let vehicle = matchedVehicles.first else { return .newRegistration }
        return vehicle.lifecycle == .active ? .activeDuplicate(vehicle) : .archivedDuplicate(vehicle)
    }
}
