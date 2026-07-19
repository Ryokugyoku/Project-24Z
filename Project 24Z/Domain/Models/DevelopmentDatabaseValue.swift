#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Foundation

/// SQLite storage classまたは明示SwiftData値を推測Decodeせず保持します。
nonisolated enum DevelopmentDatabaseValue: Equatable, Sendable {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)

    /// table cell用の省略可能な表示を返します。
    /// - Returns: NULLとstorage classを失わない短い表示。
    var cellText: String {
        switch self {
        case .null: "NULL"
        case .text(let value): String(value.prefix(160))
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .blob(let value): "BLOB · \(value.count) bytes"
        }
    }

    /// Accessibilityとdetail用のstorage class名です。
    var storageClassName: String {
        switch self {
        case .null: "NULL"
        case .text: "TEXT"
        case .integer: "INTEGER"
        case .real: "REAL"
        case .blob: "BLOB"
        }
    }

    /// detail画面で全保存値へ到達する文字列表現です。
    var detailText: String {
        switch self {
        case .null: "NULL"
        case .text(let value): value
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .blob(let value): value.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
    }
}
#endif
