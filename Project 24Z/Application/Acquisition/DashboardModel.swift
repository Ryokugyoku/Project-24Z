import Combine
import Foundation

/// ダッシュボード主操作と開始Coordinatorを接続するApplication Modelです。
@MainActor
final class DashboardModel: ObservableObject {
    /// Platformが描画する現在状態です。
    @Published private(set) var state: DashboardPresentationState

    /// 端末別候補Repositoryです。
    private let repository: any DefaultAdapterRepository

    /// 現在端末のscopeです。
    private let scope: LocalDeviceScope

    /// ログ収集開始順序を所有するCoordinatorです。
    private let coordinator: AcquisitionStartCoordinator

    /// 実停止能力が接続済みの場合だけ存在する停止Coordinatorです。
    private let stopCoordinator: (any AcquisitionStopCoordinating)?

    /// ダッシュボードModelを構成します。
    /// - Parameters:
    ///   - repository: 既定候補Repository。
    ///   - scope: 現在端末のscope。
    ///   - coordinator: 開始順序Coordinator。
    ///   - stopCoordinator: 正本順序を実行できる場合だけ注入する停止Coordinator。
    init(
        repository: any DefaultAdapterRepository,
        scope: LocalDeviceScope,
        coordinator: AcquisitionStartCoordinator,
        stopCoordinator: (any AcquisitionStopCoordinating)? = nil
    ) {
        self.repository = repository
        self.scope = scope
        self.coordinator = coordinator
        self.stopCoordinator = stopCoordinator
        state = Self.presentation(hasPrimary: false, acquisitionState: .idle, canStop: stopCoordinator != nil)
    }

    /// 保存済みPrimary状態を再読込します。
    func load() {
        let hasPrimary = (try? repository.activeCandidates(in: scope)[.primaryOBD]) != nil
        state = Self.presentation(hasPrimary: hasPrimary, acquisitionState: coordinator.state, canStop: stopCoordinator != nil)
    }

    /// 明示操作によってだけログ収集開始へ進みます。
    func startAcquisition() async {
        guard state.hasPrimaryCandidate,
              state.primaryAction.isEnabled,
              state.primaryAction.action == .startAcquisition else { return }
        await coordinator.start()
        state = Self.presentation(hasPrimary: true, acquisitionState: coordinator.state, canStop: stopCoordinator != nil)
    }

    /// 収集中Sessionを型付き停止境界へ一度だけ渡します。
    func stopAcquisition() async {
        guard let stopCoordinator,
              state.primaryAction.isEnabled,
              state.primaryAction.action == .stopAcquisition,
              let sessionID = activeSessionID(in: state.acquisitionState) else { return }
        state = Self.presentation(hasPrimary: state.hasPrimaryCandidate, acquisitionState: .stopping(sessionID: sessionID), canStop: true)
        let result = await stopCoordinator.stop(sessionID: sessionID)
        let nextState: AcquisitionStartState
        switch result {
        case .stopped:
            nextState = .stopped(sessionID: sessionID)
        case .recoveryRequired(_, let failure):
            nextState = .stopRecoveryRequired(sessionID: sessionID, failure: failure)
        case .stateUnknown(_, let failure):
            nextState = .stopStateUnknown(sessionID: sessionID, failure: failure)
        case .alreadyStopping:
            nextState = .stopping(sessionID: sessionID)
        }
        state = Self.presentation(hasPrimary: state.hasPrimaryCandidate, acquisitionState: nextState, canStop: true)
    }

    /// Secondary失敗後に利用者がPIDのみ開始を選択します。
    func confirmPIDOnlyStart() async {
        await coordinator.confirmPIDOnlyStart()
        state = Self.presentation(hasPrimary: state.hasPrimaryCandidate, acquisitionState: coordinator.state, canStop: stopCoordinator != nil)
    }

    /// 開始処理または判断待ちを利用者操作で取消します。
    func cancelStart() async {
        await coordinator.cancel()
        state = Self.presentation(hasPrimary: state.hasPrimaryCandidate, acquisitionState: coordinator.state, canStop: stopCoordinator != nil)
    }

    /// 一つの状態からボタン文言、Label、Hint、Actionを導出します。
    /// - Parameters:
    ///   - hasPrimary: Primary設定有無。
    ///   - acquisitionState: 開始・取得状態。
    /// - Returns: Platform非依存Presentation。
    static func presentation(hasPrimary: Bool, acquisitionState: AcquisitionStartState, canStop: Bool) -> DashboardPresentationState {
        let action: DashboardPrimaryActionPresentation
        let message: String
        switch acquisitionState {
        case .idle where !hasPrimary:
            action = .init(title: "接続設定をする", accessibilityLabel: "接続設定をする", accessibilityHint: "OBD・PID用Adapter候補を選択します。設定画面では接続しません。", isEnabled: true, action: .openConnectionSettings)
            message = "ログ収集にはPrimary Adapter候補の設定が必要です。"
        case .idle:
            action = .init(title: "ログ収集を開始", accessibilityLabel: "ログ収集を開始", accessibilityHint: "接続と開始前検査を行い、成功後にログを保存します。", isEnabled: true, action: .startAcquisition)
            message = "Adapter候補は設定済みです。接続と車両通信はまだ確認していません。"
        case .preflight:
            action = disabled("保存条件を確認中")
            message = "Session作成前にDB、容量、鍵を確認しています。"
        case .preparingPrimary:
            action = disabled("Primary接続中")
            message = "Primary AdapterのIdentityと能力を確認しています。"
        case .preparingSecondary:
            action = disabled("Secondary確認中")
            message = "Raw CAN receive-onlyの安全条件を確認しています。"
        case .awaitingPIDOnlyConfirmation:
            action = disabled("利用者の判断待ち")
            message = "Secondaryを開始できません。PIDのみで開始するか、キャンセルしてください。"
        case .committingSession:
            action = disabled("Session作成中")
            message = "使用するStreamを確定し、Sessionを作成しています。"
        case .acquiringPID:
            action = canStop ? .init(title: "ログ収集を停止", accessibilityLabel: "ログ収集を停止", accessibilityHint: "PIDログを安全な順序で停止します。", isEnabled: true, action: .stopAcquisition) : disabled("停止機能を利用できません")
            message = "PIDログを収集中です。"
        case .acquiringPIDAndRawCAN:
            action = canStop ? .init(title: "ログ収集を停止", accessibilityLabel: "ログ収集を停止", accessibilityHint: "PIDとRaw CANログを安全な順序で停止します。", isEnabled: true, action: .stopAcquisition) : disabled("停止機能を利用できません")
            message = "PIDとRaw CANログを収集中です。"
        case .stopping:
            action = disabled("停止中")
            message = "新規受信を止め、保存queueと確定可能なChunkを処理しています。"
        case .stopped:
            action = hasPrimary ? .init(title: "ログ収集を開始", accessibilityLabel: "ログ収集を開始", accessibilityHint: "新しいSessionでログ収集を開始します。", isEnabled: true, action: .startAcquisition) : disabled("接続設定が必要です")
            message = "ログ収集を正常終了しました。確定済みデータを保持しています。"
        case .stopRecoveryRequired(_, let failure):
            action = disabled("復旧確認が必要です")
            message = stopFailureMessage(failure, stateKnown: true)
        case .stopStateUnknown(_, let failure):
            action = disabled("状態を確認できません")
            message = stopFailureMessage(failure, stateKnown: false)
        case .failedBeforeSession(let failure):
            action = .init(title: "ログ収集を開始", accessibilityLabel: "ログ収集を再試行", accessibilityHint: "新しいConnection Generationで再試行します。", isEnabled: hasPrimary, action: .startAcquisition)
            message = failureMessage(failure, sessionExists: false)
        case .failedAfterSession(_, let failure):
            action = disabled("安全停止が必要です")
            message = failureMessage(failure, sessionExists: true)
        case .cancelled:
            action = hasPrimary ? .init(title: "ログ収集を開始", accessibilityLabel: "ログ収集を開始", accessibilityHint: "新しいConnection Generationで開始します。", isEnabled: true, action: .startAcquisition) : .init(title: "接続設定をする", accessibilityLabel: "接続設定をする", accessibilityHint: "Primary Adapter候補を選択します。", isEnabled: true, action: .openConnectionSettings)
            message = "開始を取り消しました。Sessionとログは作成していません。"
        }
        return .init(hasPrimaryCandidate: hasPrimary, acquisitionState: acquisitionState, primaryAction: action, statusMessage: message)
    }

    /// 無効な主操作Presentationを生成します。
    /// - Parameter title: 現在段階の文言。
    /// - Returns: Actionを持たないPresentation。
    private static func disabled(_ title: String) -> DashboardPrimaryActionPresentation {
        .init(title: title, accessibilityLabel: title, accessibilityHint: "処理中のため二重操作できません。", isEnabled: false, action: .none)
    }

    /// 安定失敗をデータ保持状況を含む説明へ変換します。
    /// - Parameters:
    ///   - failure: 安定失敗分類。
    ///   - sessionExists: Session commit後か。
    /// - Returns: 非機密の利用者向け説明。
    private static func failureMessage(_ failure: AcquisitionStartFailure, sessionExists: Bool) -> String {
        let prefix = sessionExists ? "Session作成後に障害が発生しました。確定済みデータは保持します。" : "開始前に停止しました。Sessionとログは作成していません。"
        switch failure {
        case .adapterIdentityMismatch: return "\(prefix) Adapter Identityが保存済みの確認結果と一致しません。接続設定から再選択してください。"
        case .adapterIdentityUnknown: return "\(prefix) Adapter Identityを確認できません。"
        case .adaptersNotDistinct: return "\(prefix) PrimaryとSecondaryを別の物理Adapterと確認できません。"
        case .permissionDenied: return "\(prefix) Bluetooth権限が拒否されています。"
        case .rawCANReceiveOnlyUnverified: return "\(prefix) Raw CAN receive-onlyの安全条件が未達です。"
        case .cancelled: return "開始を取り消しました。Sessionとログは作成していません。"
        default: return "\(prefix) 現在の構成ではログ収集を開始できません。"
        }
    }

    /// 収集中状態からSession IDだけを取り出します。
    /// - Parameter state: 現在の取得状態。
    /// - Returns: 収集中ならSession ID、それ以外は`nil`。
    private func activeSessionID(in state: AcquisitionStartState) -> UUID? {
        switch state {
        case .acquiringPID(let sessionID), .acquiringPIDAndRawCAN(let sessionID): return sessionID
        default: return nil
        }
    }

    /// 停止失敗を正常終了と区別した非機密説明へ変換します。
    /// - Parameters:
    ///   - failure: 安定停止失敗分類。
    ///   - stateKnown: `recovery_required`をDBで確認できたか。
    /// - Returns: 確定済みデータを保持する説明。
    private static func stopFailureMessage(_ failure: AcquisitionStopFailure, stateKnown: Bool) -> String {
        let state = stateKnown ? "Sessionを復旧確認が必要な状態で保持しました。" : "Sessionの終端状態を確認できません。再起動時の復旧確認が必要です。"
        switch failure {
        case .communicationFailure: return "通信停止を確認できませんでした。\(state)確定済みデータは削除していません。"
        case .persistenceFailure: return "保存queueまたはChunk確定に失敗しました。\(state)既存Chunkは削除していません。"
        case .stateUnknown: return "停止状態の確定に失敗しました。\(state)確定済みデータは削除していません。"
        }
    }
}
