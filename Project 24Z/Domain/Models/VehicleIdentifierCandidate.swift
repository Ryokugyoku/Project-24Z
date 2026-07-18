import Foundation

/// ECU応答から得た、まだvalid Identifierへ昇格していないRaw候補です。
nonisolated struct VehicleIdentifierCandidate: Equatable, Sendable {
    /// Decoderが明示した候補種別です。形状から推測しません。
    let kind: VehicleIdentifierEvidence.Kind
    /// 応答元ECUの不透明なbytesです。
    let ecuSource: Data
    /// Decoderが取り出した短寿命候補です。
    let decodedCandidate: String?
    /// 候補を根拠付ける完全なRaw responseです。
    let rawResponse: Data
}
