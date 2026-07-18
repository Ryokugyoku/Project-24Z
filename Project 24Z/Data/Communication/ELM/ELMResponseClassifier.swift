import Foundation

/// ELM応答候補を限定語彙で分類し、未知値を成功へ昇格しません。
nonisolated struct ELMResponseClassifier: Sendable {
    /// Raw応答を安定分類します。
    /// - Parameter raw: promptを含み得る未加工応答。
    /// - Returns: 既知状態、data候補、unknown、malformedのいずれか。
    func classify(_ raw: Data) -> ELMResponseEnvelope.Classification {
        guard let text = String(data: raw, encoding: .utf8) else { return .malformed }
        let normalized = text
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return .malformed }
        let joined = normalized.joined(separator: " ").uppercased()
        if joined.contains("NO DATA") { return .noData }
        if joined.contains("SEARCHING") { return .searchingProgress }
        if joined.contains("STOPPED") { return .stopped }
        if joined.contains("BUS INIT") { return .busInitialization }
        if normalized.contains(where: isHexCandidate) { return .dataCandidate }
        return .unknownStatus
    }

    /// 一行が偶数桁の16進data候補かを判定します。
    /// - Parameter line: 空白を含み得る応答行。
    /// - Returns: byte境界を満たす16進表現なら`true`。
    private func isHexCandidate(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard !compact.isEmpty, compact.count.isMultiple(of: 2) else { return false }
        return compact.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }
}
