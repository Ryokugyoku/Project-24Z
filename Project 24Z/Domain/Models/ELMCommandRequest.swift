import Foundation

/// 任意文字列を許さないELM用途別Requestです。
nonisolated enum ELMCommandRequest: Equatable, Hashable, Sendable {
    case standardOBD(OBDDiagnosticRequest)
    case adapterInputBoundaryClear
    case adapterInitializationReset
    case adapterHardwareIdentification
    case adapterFirmwareIdentification
    case adapterEchoOff
    case adapterLinefeedsOff
    case adapterSpacesOn
    case adapterHeadersOff
    case adapterProtocolAutomatic
    case adapterProtocolDescription
    case rawMonitorStart
    case rawMonitorStop
}
