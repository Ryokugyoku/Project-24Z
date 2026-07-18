import Foundation

/// 任意文字列を許さないELM用途別Requestです。
nonisolated enum ELMCommandRequest: Equatable, Hashable, Sendable {
    case standardOBD(OBDDiagnosticRequest)
    case adapterInitializationReset
    case rawMonitorStart
    case rawMonitorStop
}
