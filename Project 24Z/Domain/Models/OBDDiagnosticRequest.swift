/// Primaryだけが送信可能な上流で承認済み標準OBD診断Requestです。
nonisolated struct OBDDiagnosticRequest: Equatable, Hashable, Sendable {
    /// 書込、消去、resetを含まない読取用途です。
    enum Purpose: Equatable, Hashable, Sendable {
        case currentData(parameter: UInt8)
        case vehicleIdentification(parameter: UInt8)
    }

    let purpose: Purpose
}
