import Foundation

/// OBDLink EX／STN2232 v5.10.3で使用するread-only車両Requestの固定allowlistです。
nonisolated enum OBDLinkEXVehicleCommandAllowlist {
    /// Adapter初期化、Service 09 VIN、4つのService 01 PIDだけを許可します。
    static let version1 = VersionedELMCommandAllowlist(
        version: 1,
        adapterModel: "OBDLink EX EX101",
        firmwareVersion: "STN2232 v5.10.3",
        mode: "read_only_vehicle_identification_and_minimum_pid_probe",
        adapterResetTranscriptVerified: true,
        entries: [
            .init(request: .adapterInputBoundaryClear, bytes: Data("??\r".utf8)),
            .init(request: .adapterInitializationReset, bytes: Data("ATZ\r".utf8)),
            .init(request: .adapterHardwareIdentification, bytes: Data("STDI\r".utf8)),
            .init(request: .adapterFirmwareIdentification, bytes: Data("STI\r".utf8)),
            .init(request: .adapterEchoOff, bytes: Data("ATE0\r".utf8)),
            .init(request: .adapterLinefeedsOff, bytes: Data("ATL0\r".utf8)),
            .init(request: .adapterSpacesOn, bytes: Data("ATS1\r".utf8)),
            .init(request: .adapterHeadersOff, bytes: Data("ATH0\r".utf8)),
            .init(request: .adapterProtocolAutomatic, bytes: Data("ATSP0\r".utf8)),
            .init(request: .adapterProtocolDescription, bytes: Data("ATDP\r".utf8)),
            .init(request: .standardOBD(.init(purpose: .vehicleIdentification(parameter: 0x02))), bytes: Data("0902\r".utf8)),
            .init(request: .standardOBD(.init(purpose: .currentData(parameter: 0x04))), bytes: Data("0104\r".utf8)),
            .init(request: .standardOBD(.init(purpose: .currentData(parameter: 0x05))), bytes: Data("0105\r".utf8)),
            .init(request: .standardOBD(.init(purpose: .currentData(parameter: 0x0C))), bytes: Data("010C\r".utf8)),
            .init(request: .standardOBD(.init(purpose: .currentData(parameter: 0x0D))), bytes: Data("010D\r".utf8)),
        ]
    )
}
