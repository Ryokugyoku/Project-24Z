#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Foundation
import GRDB

/// 起動時検査済みDatabasePoolだけを読む開発専用GRDB Adapterです。
nonisolated final class GRDBDevelopmentDatabaseReader: DevelopmentDatabaseReading, @unchecked Sendable {
    /// GRDB sourceを担当します。
    let source = DevelopmentDatabaseSource.grdb

    /// Migrationやwrite能力を公開しない検査済みPoolです。
    private let databasePool: DatabasePool

    /// 読取専用Adapterを構成します。
    /// - Parameter databasePool: Production起動時検査済みPool。
    init(databasePool: DatabasePool) { self.databasePool = databasePool }

    /// sqlite内部tableを除くApplication tableを動的列挙します。
    /// - Returns: 名前順のGRDB table一覧。
    /// - Throws: schema読取失敗。
    func availableTargets() async throws -> [DevelopmentDatabaseTarget] {
        try await Task.detached { [databasePool] in
            try databasePool.read { database in
                try String.fetchAll(database, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
                    .map { .init(source: .grdb, name: $0) }
            }
        }.value
    }

    /// whitelist照合後、一回の短いread closureでpageを読みます。
    /// - Parameters:
    ///   - target: discovery済みGRDB table。
    ///   - offset: 開始offset。
    ///   - limit: 1...500の固定上限。
    /// - Returns: 全列とstorage classを保つpage。
    /// - Throws: 対象不一致または読取失敗。
    func readPage(target: DevelopmentDatabaseTarget, offset: Int, limit: Int) async throws -> DevelopmentDatabasePage {
        guard target.source == .grdb, offset >= 0, (1...500).contains(limit) else { throw ConnectionSettingsError.invalidCandidate }
        return try await Task.detached { [databasePool] in
            try databasePool.read { database in
                let discovered = try String.fetchAll(database, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
                guard discovered.contains(target.name) else { throw ConnectionSettingsError.unavailable }
                let identifier = Self.quote(target.name)
                let metadataRows = try Row.fetchAll(database, sql: "PRAGMA table_xinfo(\(identifier))")
                let columns = metadataRows.map { row in
                    DevelopmentDatabaseColumn(name: row["name"], declaredType: row["type"], primaryKeyOrdinal: row["pk"], isHidden: (row["hidden"] as Int) != 0)
                }
                let count = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(identifier)") ?? 0
                let primaryKeyColumns = columns.filter { $0.primaryKeyOrdinal > 0 }.sorted { $0.primaryKeyOrdinal < $1.primaryKeyOrdinal }
                let schemaSQL = try String.fetchOne(database, sql: "SELECT sql FROM sqlite_schema WHERE type = 'table' AND name = ?", arguments: [target.name]) ?? ""
                let ordering: String
                let notice: String?
                if !primaryKeyColumns.isEmpty {
                    ordering = primaryKeyColumns.map { Self.quote($0.name) }.joined(separator: ", ")
                    notice = "手動更新やpage間の書込みにより、厳密な同一Snapshotは保証されません。"
                } else if !schemaSQL.uppercased().contains("WITHOUT ROWID") {
                    ordering = "rowid"
                    notice = "rowid順です。page間の厳密な同一Snapshotは保証されません。"
                } else {
                    ordering = columns.map { Self.quote($0.name) }.joined(separator: ", ")
                    notice = "一意順序を保証できないため全列順です。page間で行が変化する場合があります。"
                }
                let rows = try Row.fetchAll(database, sql: "SELECT * FROM \(identifier) ORDER BY \(ordering) LIMIT ? OFFSET ?", arguments: [limit, offset])
                let values = rows.enumerated().map { index, row in
                    DevelopmentDatabaseRow(id: offset + index, values: columns.indices.map { Self.value(from: row[$0]) })
                }
                return .init(columns: columns, rows: values, offset: offset, totalRowCount: count, hasNextPage: offset + values.count < count, orderingNotice: notice)
            }
        }.value
    }

    /// discovery済みidentifierをSQLite規則でquoteします。
    /// - Parameter value: tableまたはcolumn名。
    /// - Returns: double quote済みidentifier。
    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// GRDB DatabaseValueを推測DecodeせずDomain値へ変換します。
    /// - Parameter databaseValue: SQLite保存値。
    /// - Returns: storage classを保つ値。
    private static func value(from databaseValue: DatabaseValue) -> DevelopmentDatabaseValue {
        switch databaseValue.storage {
        case .null: .null
        case .int64(let value): .integer(value)
        case .double(let value): .real(value)
        case .string(let value): .text(value)
        case .blob(let value): .blob(value)
        }
    }
}
#endif
