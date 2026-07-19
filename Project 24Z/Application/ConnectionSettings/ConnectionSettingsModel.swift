import Combine
import Foundation

/// 接続せずに候補探索・保存・解除だけを調停するApplication Modelです。
@MainActor
final class ConnectionSettingsModel: ObservableObject {
    /// Platformが描画する現在状態です。
    @Published private(set) var state: ConnectionSettingsPresentationState

    /// 認証済みUserと現在端末の保存境界です。
    let scope: LocalDeviceScope

    /// 既定候補の唯一のRepositoryです。
    private let repository: any DefaultAdapterRepository

    /// 接続能力を持たない候補探索境界です。
    private let discovery: any ConnectionEndpointDiscovering

    /// 監査日時を注入するclockです。
    private let now: () -> Date

    /// 接続設定Modelを構成します。
    /// - Parameters:
    ///   - scope: 認証済みUserとローカル端末の境界。
    ///   - repository: 既定候補Repository。
    ///   - discovery: Endpoint探索境界。Transport接続は公開しません。
    ///   - availabilityMessage: Production Hard Gate未達時の説明。
    ///   - now: 保存監査日時を返すclosure。
    init(
        scope: LocalDeviceScope,
        repository: any DefaultAdapterRepository,
        discovery: any ConnectionEndpointDiscovering,
        availabilityMessage: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.scope = scope
        self.repository = repository
        self.discovery = discovery
        self.now = now
        state = .empty(productionAvailabilityMessage: availabilityMessage)
    }

    /// 画面Actionを順序付けて実行します。
    /// - Parameter action: Viewから通知された型付き操作。
    func perform(_ action: ConnectionSettingsAction) async {
        switch action {
        case .load:
            load()
        case .beginDiscovery(let role, let transportKind):
            await beginDiscovery(role: role, transportKind: transportKind)
        case .selectCandidate(let candidate, let role):
            save(candidate, role: role)
        case .clearDefault(let role):
            clear(role: role)
        case .cancelDiscovery:
            await discovery.cancelDiscovery()
            replaceSelection(role: nil, candidates: [], message: nil)
        }
    }

    /// 保存済み候補を再読込します。
    private func load() {
        do {
            let candidates = try repository.activeCandidates(in: scope)
            replaceRoles(candidates: candidates, busyRole: nil, failureRole: nil, failureMessage: nil)
        } catch {
            replaceRoles(candidates: [:], busyRole: nil, failureRole: .primaryOBD, failureMessage: message(for: error))
        }
    }

    /// 利用者が明示したTransportだけを探索します。
    /// - Parameters:
    ///   - role: 選択対象の役割。
    ///   - transportKind: 明示選択されたTransport。
    private func beginDiscovery(role: CommunicationRole, transportKind: TransportEndpoint.Kind) async {
        replaceSelection(role: role, candidates: [], message: nil)
        do {
            let candidates = try await discovery.discoverCandidates(for: transportKind)
            let filtered = candidates.filter { candidate in
                oppositeCandidate(for: role)?.endpoint.endpointDigest != candidate.endpointDigest
            }
            replaceSelection(
                role: role,
                candidates: filtered,
                message: filtered.isEmpty ? "選択できる候補が見つかりませんでした。" : nil
            )
        } catch {
            replaceSelection(role: role, candidates: [], message: message(for: error))
        }
    }

    /// 候補を既定値として確定保存します。
    /// - Parameters:
    ///   - candidate: 利用者が選択した候補。
    ///   - role: 保存先の役割。
    private func save(_ candidate: ConnectionEndpointCandidate, role: CommunicationRole) {
        guard oppositeCandidate(for: role)?.endpoint.endpointDigest != candidate.endpointDigest else {
            replaceFailure(role: role, message: "PrimaryとSecondaryに同じEndpoint候補は設定できません。")
            return
        }
        replaceBusy(role: role)
        do {
            _ = try repository.setDefault(endpoint: candidate, role: role, in: scope, now: now())
            replaceSelection(role: nil, candidates: [], message: nil)
            load()
        } catch {
            replaceFailure(role: role, message: message(for: error))
        }
    }

    /// 対象役割だけを解除します。
    /// - Parameter role: 解除する役割。
    private func clear(role: CommunicationRole) {
        replaceBusy(role: role)
        do {
            try repository.clearDefault(role: role, in: scope, now: now())
            load()
        } catch {
            replaceFailure(role: role, message: message(for: error))
        }
    }

    /// 反対役割の確定候補を返します。
    /// - Parameter role: 現在操作中の役割。
    /// - Returns: 反対役割の候補。未設定なら`nil`。
    private func oppositeCandidate(for role: CommunicationRole) -> DefaultAdapterCandidate? {
        role == .primaryOBD ? state.secondary.candidate : state.primary.candidate
    }

    /// Repository読戻し結果で役割表示を置換します。
    /// - Parameters:
    ///   - candidates: Active候補辞書。
    ///   - busyRole: 処理中の役割。
    ///   - failureRole: 失敗を表示する役割。
    ///   - failureMessage: 安定した失敗説明。
    private func replaceRoles(
        candidates: [CommunicationRole: DefaultAdapterCandidate],
        busyRole: CommunicationRole?,
        failureRole: CommunicationRole?,
        failureMessage: String?
    ) {
        state = .init(
            primary: .init(role: .primaryOBD, candidate: candidates[.primaryOBD], isBusy: busyRole == .primaryOBD, failureMessage: failureRole == .primaryOBD ? failureMessage : nil),
            secondary: .init(role: .secondaryRawCAN, candidate: candidates[.secondaryRawCAN], isBusy: busyRole == .secondaryRawCAN, failureMessage: failureRole == .secondaryRawCAN ? failureMessage : nil),
            selectingRole: state.selectingRole,
            discoveredCandidates: state.discoveredCandidates,
            discoveryMessage: state.discoveryMessage,
            productionAvailabilityMessage: state.productionAvailabilityMessage
        )
    }

    /// 探索表示だけを置換します。
    /// - Parameters:
    ///   - role: 選択中役割。
    ///   - candidates: 表示候補。
    ///   - message: 安定した案内。
    private func replaceSelection(role: CommunicationRole?, candidates: [ConnectionEndpointCandidate], message: String?) {
        state = .init(primary: state.primary, secondary: state.secondary, selectingRole: role, discoveredCandidates: candidates, discoveryMessage: message, productionAvailabilityMessage: state.productionAvailabilityMessage)
    }

    /// 対象役割を保存中表示へ移します。
    /// - Parameter role: 処理中役割。
    private func replaceBusy(role: CommunicationRole) {
        let candidates = [
            CommunicationRole.primaryOBD: state.primary.candidate,
            CommunicationRole.secondaryRawCAN: state.secondary.candidate,
        ].compactMapValues { $0 }
        replaceRoles(candidates: candidates, busyRole: role, failureRole: nil, failureMessage: nil)
    }

    /// 対象役割へ失敗を表示し、直前の確定値を保持します。
    /// - Parameters:
    ///   - role: 失敗した役割。
    ///   - message: 安定説明。
    private func replaceFailure(role: CommunicationRole, message: String) {
        let candidates = [
            CommunicationRole.primaryOBD: state.primary.candidate,
            CommunicationRole.secondaryRawCAN: state.secondary.candidate,
        ].compactMapValues { $0 }
        replaceRoles(candidates: candidates, busyRole: nil, failureRole: role, failureMessage: message)
    }

    /// 低水準Errorを非機密の安定説明へ写像します。
    /// - Parameter error: Repositoryまたは探索境界のError。
    /// - Returns: 利用者向け説明。
    private func message(for error: Error) -> String {
        switch error as? ConnectionSettingsError {
        case .permissionDenied: "Bluetoothの使用が許可されていません。OS設定を確認してください。"
        case .permissionRestricted: "この端末ではBluetoothの使用が制限されています。"
        case .transportUnsupported: "この接続方式は現在の構成では利用できません。"
        case .noCandidates: "選択できる候補が見つかりませんでした。"
        case .duplicateRoleCandidate: "PrimaryとSecondaryに同じEndpoint候補は設定できません。"
        case .scopeMismatch: "現在の利用者または端末の設定を読み書きできません。"
        case .staleRevision: "設定が更新されたため、もう一度選択してください。"
        default: "接続設定を保存できませんでした。直前の設定は維持されています。"
        }
    }
}
