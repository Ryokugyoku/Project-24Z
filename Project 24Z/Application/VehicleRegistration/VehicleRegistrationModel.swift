import Combine
import Foundation

/// 車両登録画面の表示状態と操作拒否境界を管理します。
@MainActor
final class VehicleRegistrationModel: ObservableObject {
    /// Platformへ公開する現在状態です。
    @Published private(set) var state: VehicleRegistrationPresentationState

    /// dispatch開始から完了まで占有しているprocess内操作です。
    private var inFlightOperations: Set<VehicleRegistrationOperationKey> = []

    /// 同じpresentationで処理済みとなったprocess内操作です。
    private var processedOperations: Set<VehicleRegistrationOperationKey> = []

    /// Production Composition済みApplicationサービスを生存期間中保持します。
    private let productionServices: VehicleRegistrationProductionServices?

    /// macOS実車Discoveryの進行taskです。
    private var vehicleDiscoveryTask: Task<Void, Never>?

    /// 現在登録フローの識別結果です。VIN平文はPlatformへ公開しません。
    private var currentDiscoverySnapshot: OBDVehicleDiscoverySnapshot?

    /// 現在作成済みの識別用Sessionです。
    private var currentSessionID: UUID?

    /// 現在状態固有Actionの不透明tokenです。
    private var currentActionIdentifier = VehicleRegistrationPresentationIdentifier(UUID().uuidString)

    /// 利用者が入力した表示名です。VINその他の識別値は保持しません。
    private var pendingDisplayName: String?

    /// macOS TestFlight実車pilotの不透明な選択値です。
    private static let approvedVehicleUSBTransportSelection = VehicleRegistrationTransportSelection(
        "approved-obdlink-ex-read-only-vehicle-v1"
    )

    #if DEBUG
    /// 一App起動中に一回だけ許可するAdapter単体Probe taskです。
    private var adapterIdentityTask: Task<Void, Never>?

    /// Runbookで固定したmacOS USB Adapter単体Probeの不透明な選択値です。
    private static let approvedUSBTransportSelection = VehicleRegistrationTransportSelection(
        "development-approved-obdlink-ex-usb-v1"
    )
    #endif

    /// Compositionを経由しない呼出しを安全なblocked状態で生成します。
    init() {
        productionServices = nil
        state = .blocked(Self.productionUnavailableDisplay)
    }

    /// Production Composition済みサービスを保持し、Hard Gate未達状態を公開します。
    /// - Parameter productionServices: Data／Runtimeへ接続済みのApplicationサービス。
    init(productionServices: VehicleRegistrationProductionServices) {
        self.productionServices = productionServices
        if productionServices.vehicleDiscoverer != nil,
           productionServices.sensitiveValueProtector != nil,
           productionServices.acquisitionRepository != nil,
           productionServices.localScope != nil {
            state = Self.approvedVehicleDisconnectedState(revision: 1)
            return
        }
        #if DEBUG
        if productionServices.adapterIdentityProbe != nil {
            state = Self.approvedUSBDisconnectedState(revision: 1)
        } else {
            state = .blocked(Self.productionUnavailableDisplay(reason: productionServices.blockedReason))
        }
        #else
        state = .blocked(Self.productionUnavailableDisplay(reason: productionServices.blockedReason))
        #endif
    }

#if DEBUG
    /// Previewと単体テストだけで任意の表示状態を生成します。
    /// - Parameter previewState: 表示検証に使用するfixture状態。
    init(previewState: VehicleRegistrationPresentationState) {
        productionServices = nil
        state = previewState
    }
#endif

    /// Actionのrevisionと重複を検証し、未実装処理を成功させず拒否します。
    /// - Parameter action: Platformから通知された型付きAction。
    /// - Returns: stale、重複、未実装のいずれかの拒否結果。
    @discardableResult
    func perform(_ action: VehicleRegistrationAction) -> VehicleRegistrationActionDisposition {
        guard action.presentationRevision == state.revision else {
            return .rejectedStalePresentation
        }
        guard state.allows(action) else {
            return .rejectedInvalidState
        }
        guard hasCurrentLifecycleRevision(for: action) else {
            return .rejectedStaleLifecycleRevision
        }

        let operation = VehicleRegistrationOperationKey(action: action)
        guard !inFlightOperations.contains(operation),
              !processedOperations.contains(operation) else {
            return .rejectedDuplicateAction
        }

        inFlightOperations.insert(operation)

        if case .startConnection(let selection, _) = action,
           selection == Self.approvedVehicleUSBTransportSelection,
           let discoverer = productionServices?.vehicleDiscoverer {
            startVehicleDiscovery(discoverer, operation: operation)
            return .accepted
        }

        if case .retryIdentification = action,
           let discoverer = productionServices?.vehicleDiscoverer {
            startVehicleDiscovery(discoverer, operation: operation)
            return .accepted
        }

        if case .cancelConnection = action, vehicleDiscoveryTask != nil {
            vehicleDiscoveryTask?.cancel()
            vehicleDiscoveryTask = nil
            if let discoverer = productionServices?.vehicleDiscoverer {
                Task { await discoverer.cancel() }
            }
            inFlightOperations.removeAll()
            processedOperations.insert(operation)
            state = Self.approvedVehicleDisconnectedState(revision: state.revision.value + 1)
            return .accepted
        }

        if case .confirmRegistration(let displayName, _) = action {
            confirmCurrentRegistration(displayName: displayName, operation: operation)
            return .accepted
        }

        if case .selectExistingVehicleCandidate = action {
            confirmCurrentRegistration(displayName: nil, operation: operation)
            return .accepted
        }

        if case .confirmArchivedVehicleRestore(_, let lifecycleRevision, _) = action {
            restoreArchivedVehicle(lifecycleRevision: lifecycleRevision, operation: operation)
            return .accepted
        }

        if case .retrySessionBinding = action {
            retrySessionBinding(operation: operation)
            return .accepted
        }

        if case .endSession = action {
            endCurrentSession(operation: operation)
            return .accepted
        }

        #if DEBUG
        if case .startConnection(let selection, _) = action,
           selection == Self.approvedUSBTransportSelection,
           let probe = productionServices?.adapterIdentityProbe {
            startApprovedAdapterProbe(probe, operation: operation)
            return .accepted
        }

        if case .cancelConnection = action, adapterIdentityTask != nil {
            adapterIdentityTask?.cancel()
            adapterIdentityTask = nil
            if let probe = productionServices?.adapterIdentityProbe {
                Task { await probe.cancel() }
            }
            inFlightOperations.removeAll()
            processedOperations.insert(operation)
            state = .blocked(Self.cancelledProbeDisplay(revision: state.revision.value + 1))
            return .accepted
        }
        #endif

        inFlightOperations.remove(operation)
        processedOperations.insert(operation)
        return .rejectedUnavailable
    }

    /// AdapterからVINとPID値を取得し、暗号準備と未割当Session作成まで進めます。
    /// - Parameters:
    ///   - discoverer: read-only固定allowlistの実車境界。
    ///   - operation: 二重実行を拒否する操作Key。
    private func startVehicleDiscovery(
        _ discoverer: any OBDVehicleDiscovering,
        operation: VehicleRegistrationOperationKey
    ) {
        let workRevision = state.revision.value + 1
        currentActionIdentifier = VehicleRegistrationPresentationIdentifier(UUID().uuidString)
        state = .identifying(
            VehicleRegistrationDisplayValues(
                title: "車両を識別中",
                message: "Adapter identityを照合し、read-onlyのVINと最小PIDを順番に取得しています。",
                adapterDisplayName: "OBDLink EX (EX101)",
                progress: nil,
                sessionSummary: "識別成功後に未割当Sessionを一度だけ作成します。",
                isCancellationAvailable: true,
                revision: VehicleRegistrationPresentationRevision(workRevision)
            )
        )
        vehicleDiscoveryTask = Task { [weak self] in
            do {
                let snapshot = try await discoverer.discoverVehicle()
                guard !Task.isCancelled else { return }
                try self?.prepareRegistration(from: snapshot)
                self?.finishOperation(operation)
            } catch is CancellationError {
                return
            } catch {
                self?.failVehicleDiscovery(operation: operation, workRevision: workRevision)
            }
        }
    }

    /// 実応答Snapshotを暗号化し、GRDB Sessionと既存Workflowへ接続します。
    /// - Parameter discovery: 一意なVINと成功PID値を持つSnapshot。
    /// - Throws: 暗号、DB、Workflowのいずれかが不成立の場合。
    private func prepareRegistration(from discovery: OBDVehicleDiscoverySnapshot) throws {
        guard let services = productionServices,
              let protector = services.sensitiveValueProtector,
              let acquisitionRepository = services.acquisitionRepository,
              let scope = services.localScope else {
            throw VehicleRegistrationWorkflow.Error.unavailable
        }
        let now = Date()
        let generation = ConnectionGeneration(value: UInt64(max(1, state.revision.value)))
        let attemptID = UUID()
        let encryptedVIN = try protector.encrypt(Data(discovery.vin.utf8))
        let encryptedRaw = try protector.encrypt(discovery.rawVINResponse)
        let evidence = VehicleIdentifierEvidence(
            identifierID: UUID(),
            kind: .vin,
            encryptedNormalizedValue: encryptedVIN,
            lookupDigest: try protector.lookupDigest(for: discovery.vin),
            digestKeyVersion: 1
        )
        let value = ECUIdentificationValueSnapshot(
            valueID: UUID(),
            infoTypeCode: 0x02,
            occurrenceOrdinal: 0,
            valueKind: .vin,
            decodeState: .decoded,
            validationState: .valid,
            encryptedDecodedValue: encryptedVIN,
            encryptedRawResponse: encryptedRaw
        )
        let scan = VehicleIdentificationScanSnapshot(
            scanID: UUID(),
            obdConnectionID: discovery.connectionID,
            transportKind: "usb_serial",
            diagnosticProtocolKind: String(discovery.diagnosticProtocol.prefix(64)),
            adapterReferenceID: "obdlink-ex-ex101",
            decoderVersion: "obdlink-read-only-v1",
            normalizationVersion: "vin-shape-v1",
            status: .completed,
            decodeState: .decoded,
            identityValidationState: .valid,
            terminationReasonCode: nil,
            startedAt: discovery.successfulPIDValues.map(\.observedAt).min() ?? now,
            finishedAt: now,
            observations: [
                ECUObservationSnapshot(
                    observationID: UUID(),
                    ordinal: 0,
                    addressFormat: .unknown,
                    responderAddress: Data([0]),
                    values: [value]
                ),
            ]
        )

        let sessionID = UUID()
        let session = AcquisitionSession(
            sessionID: sessionID,
            vehicleID: nil,
            vehicleBindingState: .unassignedUnidentified,
            captureState: .recording,
            dispositionState: .pendingDecision,
            integrityState: .unchecked,
            endReason: nil,
            startedAt: now,
            endedAt: nil,
            createdByDeviceID: scope.localDeviceScopeID,
            revision: 1,
            updatedAt: now,
            updatedByDeviceID: scope.localDeviceScopeID
        )
        let stream = AcquisitionStream(
            streamID: UUID(),
            sessionID: sessionID,
            kind: .obdPID,
            adapterRole: .primary,
            adapterReferenceID: "obdlink-ex-ex101",
            connectionInstanceID: discovery.connectionID,
            state: .active,
            startedAt: now,
            endedAt: nil,
            nextRecordSequence: 0,
            nextChunkSequence: 0,
            revision: 1,
            updatedAt: now
        )
        let epoch = AcquisitionClockEpoch(
            clockEpochID: UUID(),
            sessionID: sessionID,
            processInstanceID: UUID(),
            deviceID: scope.localDeviceScopeID,
            wallClockAnchor: now,
            anchorUncertaintyNanoseconds: 0,
            startedAt: now
        )
        try acquisitionRepository.start(session: session, streams: [stream], epoch: epoch)

        let context = VehicleRegistrationWorkflowContext(
            request: VehicleRegistrationRequest(
                proposedVehicleID: UUID(),
                encryptedDisplayName: nil,
                identifiers: [evidence],
                scan: scan,
                deviceID: scope.localDeviceScopeID,
                recordedAt: now
            ),
            connectionGeneration: generation,
            scanAttemptID: attemptID,
            sessionID: sessionID,
            sessionRevision: 1
        )
        services.workflow.beginIdentification(generation: generation, attemptID: attemptID)
        try services.workflow.receivePreparedRegistration(context, generation: generation, attemptID: attemptID)
        currentDiscoverySnapshot = discovery
        currentSessionID = sessionID
        services.telemetryModel.apply(discovery)
        applyWorkflowPresentation()
    }

    /// 新規または一意な既存候補の登録transactionを実行します。
    /// - Parameters:
    ///   - displayName: 任意表示名。
    ///   - operation: 完了対象操作。
    private func confirmCurrentRegistration(
        displayName: String?,
        operation: VehicleRegistrationOperationKey
    ) {
        do {
            guard let services = productionServices, let protector = services.sensitiveValueProtector else {
                throw VehicleRegistrationWorkflow.Error.unavailable
            }
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingDisplayName = trimmed?.isEmpty == false ? trimmed : nil
            let encryptedName = try pendingDisplayName.map { try protector.encrypt(Data($0.utf8)) }
            try services.workflow.updatePendingDisplayName(encryptedName)
            try services.workflow.confirmRegistration(
                operationID: UUID(),
                expectedRevision: services.workflow.state.revision
            )
            applyWorkflowPresentation()
        } catch {
            applyWorkflowPresentation(fallbackFailure: true)
        }
        finishOperation(operation)
    }

    /// archived候補を期待Lifecycle Revisionで明示復元します。
    /// - Parameters:
    ///   - lifecycleRevision: UIが確認したRevision。
    ///   - operation: 完了対象操作。
    private func restoreArchivedVehicle(
        lifecycleRevision: Int,
        operation: VehicleRegistrationOperationKey
    ) {
        do {
            guard let workflow = productionServices?.workflow else { throw VehicleRegistrationWorkflow.Error.unavailable }
            try workflow.restoreArchivedVehicle(
                expectedLifecycleRevision: lifecycleRevision,
                expectedRevision: workflow.state.revision
            )
            applyWorkflowPresentation()
        } catch {
            applyWorkflowPresentation(fallbackFailure: true)
        }
        finishOperation(operation)
    }

    /// binding pendingの登録済みSessionを再試行します。
    /// - Parameter operation: 完了対象操作。
    private func retrySessionBinding(operation: VehicleRegistrationOperationKey) {
        do {
            guard let workflow = productionServices?.workflow else { throw VehicleRegistrationWorkflow.Error.unavailable }
            try workflow.retrySessionBinding(expectedRevision: workflow.state.revision)
            applyWorkflowPresentation()
        } catch {
            applyWorkflowPresentation(fallbackFailure: true)
        }
        finishOperation(operation)
    }

    /// 登録済み識別Sessionを既存GRDB停止transactionで終了します。
    /// - Parameter operation: 完了対象操作。
    private func endCurrentSession(operation: VehicleRegistrationOperationKey) {
        do {
            guard let repository = productionServices?.acquisitionStopRepository,
                  let scope = productionServices?.localScope,
                  let sessionID = currentSessionID else {
                throw VehicleRegistrationWorkflow.Error.unavailable
            }
            let stopContext = try repository.requestStop(
                sessionID: sessionID,
                requestedAt: Date(),
                deviceID: scope.localDeviceScopeID
            )
            try repository.completeStop(
                stopContext,
                endedAt: Date().addingTimeInterval(0.000_001),
                deviceID: scope.localDeviceScopeID
            )
            let revision = state.revision.value + 1
            state = .registered(
                VehicleRegistrationRegisteredPresentation(
                    sessionBindingState: .bound,
                    display: registeredDisplay(revision: revision, sessionEnded: true)
                )
            )
        } catch {
            applyWorkflowPresentation(fallbackFailure: true)
        }
        finishOperation(operation)
    }

    /// Workflowの論理Stateを機密値を含まないPlatform Presentationへ変換します。
    /// - Parameter fallbackFailure: 想定外の変換時にfailed表示へ進めるか。
    private func applyWorkflowPresentation(fallbackFailure: Bool = false) {
        guard let workflow = productionServices?.workflow else { return }
        let revision = state.revision.value + 1
        switch workflow.state {
        case .registrationReady:
            state = .registrationReady(registrationReadyDisplay(revision: revision))
        case .activeDuplicate(_, let vehicle, _):
            state = .duplicateCandidate(
                VehicleRegistrationDuplicateCandidate(
                    lifecycle: .active,
                    lifecycleRevision: vehicle.lifecycleRevision,
                    display: duplicateDisplay(revision: revision, archived: false)
                )
            )
        case .archivedDuplicate(_, let vehicle, _):
            state = .duplicateCandidate(
                VehicleRegistrationDuplicateCandidate(
                    lifecycle: .archived,
                    lifecycleRevision: vehicle.lifecycleRevision,
                    display: duplicateDisplay(revision: revision, archived: true)
                )
            )
        case .archivedRestoreRequired(_, let vehicle, _):
            state = .archivedRestoreRequired(
                VehicleRegistrationDuplicateCandidate(
                    lifecycle: .archived,
                    lifecycleRevision: vehicle.lifecycleRevision,
                    display: duplicateDisplay(revision: revision, archived: true)
                )
            )
        case .registered(_, let bindingPending, _, _):
            state = .registered(
                VehicleRegistrationRegisteredPresentation(
                    sessionBindingState: bindingPending ? .pending : .bound,
                    display: registeredDisplay(revision: revision, sessionEnded: false)
                )
            )
        case .conflict:
            state = .conflict(failureDisplay(title: "車両候補が競合しています", revision: revision))
        case .blocked, .transactionResultUnknown:
            state = .blocked(failureDisplay(title: "登録結果を確定できません", revision: revision))
        case .failed:
            state = .failed(failureDisplay(title: "車両登録に失敗しました", revision: revision))
        default:
            if fallbackFailure {
                state = .failed(failureDisplay(title: "車両登録を完了できませんでした", revision: revision))
            }
        }
    }

    /// Async操作を一度だけ完了扱いにします。
    /// - Parameter operation: 完了する操作Key。
    private func finishOperation(_ operation: VehicleRegistrationOperationKey) {
        vehicleDiscoveryTask = nil
        inFlightOperations.remove(operation)
        processedOperations.insert(operation)
    }

    /// 実車Discovery失敗を再試行可能なfailed状態へ変換します。
    /// - Parameters:
    ///   - operation: 完了する操作Key。
    ///   - workRevision: Discovery開始時Revision。
    private func failVehicleDiscovery(
        operation: VehicleRegistrationOperationKey,
        workRevision: Int
    ) {
        guard state.revision.value == workRevision else { return }
        productionServices?.telemetryModel.markStale()
        state = .failed(
            VehicleRegistrationDisplayValues(
                title: "車両を識別できませんでした",
                message: "USB、Adapter identity、VIN応答、暗号化、GRDB保存のいずれかを確定できませんでした。",
                adapterDisplayName: "OBDLink EX (EX101)",
                sessionSummary: "成功していない処理を車両登録済みとして扱いません。",
                unavailableReason: "Transportは閉じました。イグニッションと接続を確認して再試行してください。",
                revision: VehicleRegistrationPresentationRevision(workRevision + 1)
            )
        )
        finishOperation(operation)
    }

    /// macOS TestFlightで実車read-only pilotを開始できる接続前状態です。
    /// - Parameter revision: 表示Revision。
    /// - Returns: Endpoint秘密値を含まないOBDLink EX候補。
    private static func approvedVehicleDisconnectedState(
        revision: Int
    ) -> VehicleRegistrationPresentationState {
        .disconnected(
            VehicleRegistrationDisconnectedPresentation(
                display: VehicleRegistrationDisplayValues(
                    title: "OBDLink EXで車両を登録",
                    message: "VINと4つの標準PIDをread-only要求で取得し、結果を確認してから登録します。",
                    adapterDisplayName: "OBDLink EX (EX101)",
                    sessionSummary: "成功時だけ暗号化済み識別SessionをGRDBへ作成します。",
                    unavailableReason: "初回実車条件はユーザー確認対象です。書込み・消去・任意commandは実行しません。",
                    revision: VehicleRegistrationPresentationRevision(revision)
                ),
                transportOptions: [
                    VehicleRegistrationTransportOption(
                        transportSelection: approvedVehicleUSBTransportSelection,
                        adapterSelection: VehicleRegistrationPresentationIdentifier("obdlink-ex-ex101-v1"),
                        displayName: "OBDLink EX USB（read-only実車pilot）",
                        isSelected: true
                    ),
                ]
            )
        )
    }

    /// 新規登録確認用のmask済み表示を作ります。
    /// - Parameter revision: 表示Revision。
    /// - Returns: VIN平文を含まない登録確認表示。
    private func registrationReadyDisplay(revision: Int) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "車両を識別しました",
            message: "一意な既存車両には一致しませんでした。表示名を確認して登録できます。",
            maskedIdentifier: maskedVIN,
            adapterDisplayName: currentDiscoverySnapshot?.adapterIdentity.displayName,
            sessionSummary: "未割当の識別Sessionを保持しています。登録後に車両へ所属させます。",
            revision: VehicleRegistrationPresentationRevision(revision),
            actionIdentifier: currentActionIdentifier
        )
    }

    /// 既存候補確認用のmask済み表示を作ります。
    /// - Parameters:
    ///   - revision: 表示Revision。
    ///   - archived: archived候補か。
    /// - Returns: 候補状態を明示する表示。
    private func duplicateDisplay(revision: Int, archived: Bool) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: archived ? "アーカイブ済み車両に一致" : "登録済み車両に一致",
            message: archived
                ? "識別Scanを保持した後、明示的な復元確認が必要です。"
                : "識別子が一意に一致しました。この車両へSessionを所属できます。",
            maskedIdentifier: maskedVIN,
            adapterDisplayName: currentDiscoverySnapshot?.adapterIdentity.displayName,
            sessionSummary: "確認前は未割当Sessionのままです。",
            revision: VehicleRegistrationPresentationRevision(revision),
            actionIdentifier: currentActionIdentifier
        )
    }

    /// 登録・Session所属済み表示を作ります。
    /// - Parameters:
    ///   - revision: 表示Revision。
    ///   - sessionEnded: 識別Sessionを終了済みか。
    /// - Returns: 登録結果表示。
    private func registeredDisplay(revision: Int, sessionEnded: Bool) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "車両登録が完了しました",
            message: "VINは暗号化し、照合用Digestと分離してGRDBへ保存しました。",
            maskedIdentifier: maskedVIN,
            vehicleDisplayName: pendingDisplayName,
            adapterDisplayName: currentDiscoverySnapshot?.adapterIdentity.displayName,
            sessionSummary: sessionEnded
                ? "車両所属を確定した識別Sessionを正常終了しました。"
                : "識別Sessionの車両所属を確定しました。必要ならSessionを終了してください。",
            revision: VehicleRegistrationPresentationRevision(revision),
            actionIdentifier: currentActionIdentifier
        )
    }

    /// 登録失敗や競合の安全な表示を作ります。
    /// - Parameters:
    ///   - title: 安定見出し。
    ///   - revision: 表示Revision。
    /// - Returns: VIN平文や例外文を含まない失敗表示。
    private func failureDisplay(title: String, revision: Int) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: title,
            message: "成功を推測せず、保存済みの識別SessionとRaw evidenceを保持します。",
            maskedIdentifier: maskedVIN,
            adapterDisplayName: currentDiscoverySnapshot?.adapterIdentity.displayName,
            sessionSummary: "Sessionを自動削除しません。再試行または終了を選択してください。",
            unavailableReason: "Repositoryの再確認またはユーザー判断が必要です。",
            revision: VehicleRegistrationPresentationRevision(revision),
            actionIdentifier: currentActionIdentifier
        )
    }

    /// 現在VINの末尾4文字だけを表示用に返します。
    private var maskedVIN: String? {
        guard let vin = currentDiscoverySnapshot?.vin else { return nil }
        return "•••••••••••••\(vin.suffix(4))"
    }

    #if DEBUG
    /// 承認済みAdapter単体Probeを開始し、結果を車両識別成功へ昇格せず表示します。
    /// - Parameters:
    ///   - probe: exact Descriptor／command／responseを検証する境界。
    ///   - operation: 二重実行を拒否するprocess内操作Key。
    private func startApprovedAdapterProbe(
        _ probe: any AdapterIdentityProbing,
        operation: VehicleRegistrationOperationKey
    ) {
        let workRevision = state.revision.value + 1
        state = .adapterChecking(
            VehicleRegistrationDisplayValues(
                title: "USB Adapterを確認中",
                message: "承認済みのOBDLink EX DescriptorとAdapter単体transcriptを1回だけ照合しています。",
                adapterDisplayName: "OBDLink EX (EX101)",
                sessionSummary: "車両向けRequestとAcquisition Sessionは開始していません。",
                isCancellationAvailable: true,
                revision: VehicleRegistrationPresentationRevision(workRevision)
            )
        )
        adapterIdentityTask = Task { [weak self] in
            do {
                let identity = try await probe.verifyApprovedAdapter()
                guard !Task.isCancelled else { return }
                self?.finishApprovedAdapterProbe(identity, operation: operation, workRevision: workRevision)
            } catch is CancellationError {
                return
            } catch {
                self?.failApprovedAdapterProbe(operation: operation, workRevision: workRevision)
            }
        }
    }

    /// Adapter単体identity成功を車両識別未実施のblocked状態として確定します。
    /// - Parameters:
    ///   - identity: transcriptと一致した非機密Adapter identity。
    ///   - operation: 完了する操作Key。
    ///   - workRevision: Probe開始時の表示Revision。
    private func finishApprovedAdapterProbe(
        _ identity: VerifiedAdapterIdentity,
        operation: VehicleRegistrationOperationKey,
        workRevision: Int
    ) {
        guard state.revision.value == workRevision else { return }
        adapterIdentityTask = nil
        inFlightOperations.remove(operation)
        processedOperations.insert(operation)
        state = .blocked(
            VehicleRegistrationDisplayValues(
                title: "USB Adapter確認済み",
                message: "\(identity.hardwareVersion)／\(identity.firmwareVersion)とのUSB双方向通信を確認し、安全に切断しました。",
                adapterDisplayName: identity.displayName,
                sessionSummary: "車両向けRequestとAcquisition Sessionは開始していません。",
                unavailableReason: "車両OBD Requestのexact bytesと実車応答が未検証です。",
                actionDisabledReason: "この証拠だけでは車両識別・登録・ログ収集を開始できません。",
                revision: VehicleRegistrationPresentationRevision(workRevision + 1)
            )
        )
    }

    /// Probe失敗を再試行可能な成功へ変換せず、一App起動中の実行を停止します。
    /// - Parameters:
    ///   - operation: 完了する操作Key。
    ///   - workRevision: Probe開始時の表示Revision。
    private func failApprovedAdapterProbe(
        operation: VehicleRegistrationOperationKey,
        workRevision: Int
    ) {
        guard state.revision.value == workRevision else { return }
        adapterIdentityTask = nil
        inFlightOperations.remove(operation)
        processedOperations.insert(operation)
        state = .blocked(
            VehicleRegistrationDisplayValues(
                title: "USB Adapterを確認できませんでした",
                message: "Endpoint数、USB Descriptor、115200/8N1、identity応答のいずれかが承認済み条件と一致しません。",
                adapterDisplayName: "OBDLink EX (EX101)",
                sessionSummary: "車両向けRequestとAcquisition Sessionは開始していません。",
                unavailableReason: "想定外状態のためTransportを閉じ、このApp起動中の追加送信を停止しました。",
                actionDisabledReason: "物理構成を確認し、新しい承認単位でAppを再起動してください。",
                revision: VehicleRegistrationPresentationRevision(workRevision + 1)
            )
        )
    }
    #endif

    /// archived復元Actionのlifecycle revisionが現在候補と一致するかを返します。
    /// - Parameter action: 検証する型付きAction。
    /// - Returns: lifecycle revision検証が不要、または現在値と一致する場合は`true`。
    private func hasCurrentLifecycleRevision(for action: VehicleRegistrationAction) -> Bool {
        guard case .confirmArchivedVehicleRestore(_, let lifecycleRevision, _) = action else {
            return true
        }
        guard case .archivedRestoreRequired(let candidate) = state else {
            return false
        }
        return lifecycleRevision == candidate.lifecycleRevision
    }

    /// Productionで表示する安定した利用不能状態です。
    private static var productionUnavailableDisplay: VehicleRegistrationDisplayValues {
        productionUnavailableDisplay(
            reason: "Production Compositionが提供されていません。"
        )
    }

    /// Production Hard Gate理由を持つ安全な利用不能表示を生成します。
    /// - Parameter reason: 機密情報を含まない安定した停止理由。
    /// - Returns: 登録成功を表さないblocked表示値。
    private static func productionUnavailableDisplay(
        reason: String
    ) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "車両登録は利用できません",
            message: "安全条件を満たすまでProductionの接続・識別・登録を開始しません。",
            sessionSummary: "Sessionは車両未割当のまま保持されます。",
            unavailableReason: reason,
            actionDisabledReason: "接続、識別、登録、復元、Session所属は現在実行できません。",
            revision: VehicleRegistrationPresentationRevision(1)
        )
    }

    #if DEBUG
    /// 承認済みDevelopment Probeを一回だけ開始できる接続前状態です。
    /// - Parameter revision: 表示Revision。
    /// - Returns: Endpoint秘密値を含まないOBDLink EX USB選択肢。
    private static func approvedUSBDisconnectedState(
        revision: Int
    ) -> VehicleRegistrationPresentationState {
        .disconnected(
            VehicleRegistrationDisconnectedPresentation(
                display: VehicleRegistrationDisplayValues(
                    title: "USB Adapter単体確認",
                    message: "実車アクセス承認後に、OBDLink EXのHost-to-Adapter identityだけを各1回確認します。",
                    adapterDisplayName: "OBDLink EX (EX101)",
                    sessionSummary: "車両向けRequestとAcquisition Sessionは開始しません。",
                    unavailableReason: "車両OBD識別とProduction Transportは引き続きblockedです。",
                    revision: VehicleRegistrationPresentationRevision(revision)
                ),
                transportOptions: [
                    VehicleRegistrationTransportOption(
                        transportSelection: approvedUSBTransportSelection,
                        adapterSelection: VehicleRegistrationPresentationIdentifier(
                            "development-approved-obdlink-ex-adapter-v1"
                        ),
                        displayName: "OBDLink EX USB（承認済み1回）",
                        isSelected: true
                    ),
                ]
            )
        )
    }

    /// 利用者取消し後に追加送信を止めるblocked表示です。
    /// - Parameter revision: 次の表示Revision。
    /// - Returns: 再起動と再承認を要求するblocked表示。
    private static func cancelledProbeDisplay(
        revision: Int
    ) -> VehicleRegistrationDisplayValues {
        VehicleRegistrationDisplayValues(
            title: "USB Adapter確認を取り消しました",
            message: "Transport closeを要求し、このApp起動中の追加送信を停止しました。",
            adapterDisplayName: "OBDLink EX (EX101)",
            sessionSummary: "車両向けRequestとAcquisition Sessionは開始していません。",
            unavailableReason: "取消し後の自動再試行は行いません。",
            actionDisabledReason: "再実行には新しい承認単位でAppを再起動してください。",
            revision: VehicleRegistrationPresentationRevision(revision)
        )
    }
    #endif
}
