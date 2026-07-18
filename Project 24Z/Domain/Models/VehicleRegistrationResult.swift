import Foundation

/// 登録transactionの永続結果です。
enum VehicleRegistrationResult: Equatable, Sendable {
    /// 新規またはactive既存車両へ収束しました。
    case registered(VehicleIdentity)
    /// archived既存車両へScanだけを追加し、明示復元を待ちます。
    case archivedRestoreRequired(VehicleIdentity)
}
