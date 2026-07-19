#if PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER
import Foundation
import GRDB
import Testing
@testable import Project_24Z

/// 開発専用GRDB Browserのschema discovery、値保持、paging、read-onlyを検証します。
@Suite(.serialized)
struct GRDBDevelopmentDatabaseReaderTests {
    /// 内部tableを除外し、NULLと全storage classを区別してpage読込します。
    @Test
    func discoversApplicationTablesAndPreservesStorageClasses() async throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let pool = try DatabasePool(path: fixture.url.path)
        try await pool.write { database in
            try database.execute(sql: "CREATE TABLE grdb_migrations(identifier TEXT PRIMARY KEY)")
            try database.execute(sql: "CREATE TABLE sample(id INTEGER PRIMARY KEY, text_value TEXT, real_value REAL, blob_value BLOB, null_value TEXT)")
            try database.execute(sql: "INSERT INTO sample VALUES (1, '', 1.25, X'00ff', NULL), (2, 'second', 2.5, X'', NULL)")
        }
        let before = try databaseSnapshot(pool)
        let reader = GRDBDevelopmentDatabaseReader(databasePool: pool)

        let targets = try await reader.availableTargets()
        #expect(targets.map(\.name).contains("grdb_migrations"))
        #expect(targets.map(\.name).contains("sample"))
        #expect(!targets.map(\.name).contains(where: { $0.hasPrefix("sqlite_") }))
        let first = try await reader.readPage(target: .init(source: .grdb, name: "sample"), offset: 0, limit: 1)
        #expect(first.rows.count == 1)
        #expect(first.hasNextPage)
        #expect(first.rows[0].values == [.integer(1), .text(""), .real(1.25), .blob(Data([0x00, 0xff])), .null])
        let second = try await reader.readPage(target: .init(source: .grdb, name: "sample"), offset: 1, limit: 1)
        #expect(second.rows[0].id == 1)
        #expect(!second.hasNextPage)
        #expect(try databaseSnapshot(pool) == before)
    }

    /// discovery外の悪意あるidentifier相当入力を任意SQLとして実行しません。
    @Test
    func rejectsUndiscoveredIdentifier() async throws {
        let fixture = try TemporaryVehicleDatabase()
        defer { fixture.remove() }
        let pool = try DatabasePool(path: fixture.url.path)
        try await pool.write { try $0.execute(sql: "CREATE TABLE safe(value TEXT)") }
        let reader = GRDBDevelopmentDatabaseReader(databasePool: pool)

        await #expect(throws: (any Error).self) {
            try await reader.readPage(target: DevelopmentDatabaseTarget(source: .grdb, name: "safe; DROP TABLE safe;--"), offset: 0, limit: 10)
        }
        let stillExists = try await pool.read { try $0.tableExists("safe") }
        #expect(stillExists)
    }

    /// Browser操作前後を比較する物理行Snapshotを作ります。
    /// - Parameter pool: 検証対象Pool。
    /// - Returns: schema SQLと全sample値を連結したData。
    private func databaseSnapshot(_ pool: DatabasePool) throws -> Data {
        try pool.read { database in
            let schema = try String.fetchAll(database, sql: "SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name").joined()
            let rows = try Row.fetchAll(database, sql: "SELECT quote(id), quote(text_value), quote(real_value), quote(blob_value), quote(null_value) FROM sample ORDER BY id")
            return Data((schema + rows.description).utf8)
        }
    }
}
#endif
