/// Validation結果と既存車両照合から得る登録可否です。
nonisolated enum VehicleRegistrationEligibility: Equatable, Sendable {
    /// 有効なIdentifierがなく登録できません。
    case blocked
    /// 一つの有効Identifierで新規登録できます。
    case newRegistration
    /// 一意なactive既存車両候補です。
    case activeDuplicate(VehicleIdentity)
    /// 一意なarchived既存車両候補です。
    case archivedDuplicate(VehicleIdentity)
    /// 候補または一致結果が競合しています。
    case conflict
}
