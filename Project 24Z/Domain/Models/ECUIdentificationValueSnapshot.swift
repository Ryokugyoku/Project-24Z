import Foundation

/// 一つのECUから得た一つの識別値の終端Snapshotです。
nonisolated struct ECUIdentificationValueSnapshot: Equatable, Sendable {
    /// Decode済み値の意味を示す安定コードです。
    enum ValueKind: String, Equatable, Sendable {
        case vin
        case domesticChassisNumber = "domestic_chassis_number"
        case ecuName = "ecu_name"
        case calibrationID = "calibration_id"
        case cvn
        case engineSerialNumber = "engine_serial_number"
        case engineFamily = "engine_family"
        case otherKnownIdentification = "other_known_identification"
        case unknownStandardInfoType = "unknown_standard_info_type"
    }

    /// Decode結果です。
    enum DecodeState: String, Equatable, Sendable {
        case decoded
        case notDecodable = "not_decodable"
        case unsupported
    }

    /// 値のValidation結果です。
    enum ValidationState: String, Equatable, Sendable {
        case valid
        case invalid
        case notApplicable = "not_applicable"
        case notEvaluated = "not_evaluated"
    }

    /// 識別値行UUIDです。
    let valueID: UUID
    /// 受信した標準InfoTypeのbyte値です。
    let infoTypeCode: UInt8
    /// 同じInfoType内の0始まり出現順です。
    let occurrenceOrdinal: Int
    /// 値の意味です。
    let valueKind: ValueKind
    /// Decode状態です。
    let decodeState: DecodeState
    /// Validation状態です。
    let validationState: ValidationState
    /// Decodeできた場合の暗号化済み値です。
    let encryptedDecodedValue: EncryptedVehicleValue?
    /// 完全なRaw Responseの暗号文です。
    let encryptedRawResponse: EncryptedVehicleValue
}
