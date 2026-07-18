import Foundation
@testable import Project_24Z

/// 暗号方式を主張しない、長さ条件だけを満たすRepositoryテスト入力です。
enum VehicleIdentityTestFixtures {
    /// 固定日時です。
    static let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)
    /// 固定scope UUIDです。
    static let scopeID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    /// 固定device UUIDです。
    static let deviceID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

    /// 最低長を満たす不透明なテスト暗号文を作ります。
    /// - Parameter byte: 内容を識別する固定byte。
    /// - Returns: 暗号方式の証拠として使わない30 byte値。
    static func encrypted(_ byte: UInt8) -> EncryptedVehicleValue {
        EncryptedVehicleValue(ciphertext: Data(repeating: byte, count: 30), keyVersion: 1)
    }

    /// 一つのVIN根拠と一ECU・一値を持つvalid登録要求を作ります。
    /// - Parameters:
    ///   - vehicleID: 提案車両UUID。
    ///   - scanID: Scan UUID。
    ///   - connectionID: OBD接続UUID。
    ///   - digestByte: Digest内容。
    /// - Returns: Repositoryへ渡せる不変要求。
    static func registrationRequest(
        vehicleID: UUID = UUID(),
        scanID: UUID = UUID(),
        connectionID: UUID = UUID(),
        digestByte: UInt8 = 7
    ) -> VehicleRegistrationRequest {
        let value = ECUIdentificationValueSnapshot(
            valueID: UUID(),
            infoTypeCode: 2,
            occurrenceOrdinal: 0,
            valueKind: .vin,
            decodeState: .decoded,
            validationState: .valid,
            encryptedDecodedValue: encrypted(3),
            encryptedRawResponse: encrypted(4)
        )
        let observation = ECUObservationSnapshot(
            observationID: UUID(),
            ordinal: 0,
            addressFormat: .can11Bit,
            responderAddress: Data([0x07, 0xE8]),
            values: [value]
        )
        return VehicleRegistrationRequest(
            proposedVehicleID: vehicleID,
            encryptedDisplayName: nil,
            identifiers: [
                VehicleIdentifierEvidence(
                    identifierID: UUID(),
                    kind: .vin,
                    encryptedNormalizedValue: encrypted(1),
                    lookupDigest: Data(repeating: digestByte, count: 32),
                    digestKeyVersion: 1
                )
            ],
            scan: VehicleIdentificationScanSnapshot(
                scanID: scanID,
                obdConnectionID: connectionID,
                transportKind: "bluetooth_le",
                diagnosticProtocolKind: "iso_15765_4",
                adapterReferenceID: "adapter-reference",
                decoderVersion: "decoder-v1",
                normalizationVersion: "normalization-v1",
                status: .completed,
                decodeState: .decoded,
                identityValidationState: .valid,
                terminationReasonCode: nil,
                startedAt: recordedAt.addingTimeInterval(-2),
                finishedAt: recordedAt.addingTimeInterval(-1),
                observations: [observation]
            ),
            deviceID: deviceID,
            recordedAt: recordedAt
        )
    }
}
