import Foundation

/// 車両登録とは別transactionで取得Sessionをactive車両へ所属させる境界です。
protocol SessionVehicleBindingRepository {
    /// 未割当Sessionを、期待Revisionと登録根拠を再確認して一度だけ所属させます。
    /// - Parameters:
    ///   - sessionID: 未割当SessionのUUID。
    ///   - vehicleID: active確認済み車両UUID。
    ///   - expectedSessionRevision: 呼び出し側が読んだSession Revision。
    ///   - expectedVehicleLifecycleRevision: 登録完了時のLifecycle Revision。
    /// - Throws: 保存確定済み、別車両所属、archive、Revision競合、利用不能時のエラー。
    func bind(
        sessionID: UUID,
        vehicleID: UUID,
        expectedSessionRevision: Int,
        expectedVehicleLifecycleRevision: Int
    ) throws
}
