/// ログ収集停止が正常終了へ進めなかった安定分類です。
nonisolated enum AcquisitionStopFailure: Error, Equatable, Sendable {
    /// PIDまたはRaw CANの停止状態を確認できませんでした。
    case communicationFailure
    /// 保存queueまたはChunk確定に失敗しました。
    case persistenceFailure
    /// Session状態を確定できませんでした。
    case stateUnknown
}
