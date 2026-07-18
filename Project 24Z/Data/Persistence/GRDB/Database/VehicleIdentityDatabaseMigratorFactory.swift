import Foundation
import GRDB

/// Vehicle Identity Storeの追記式Migrationを構成します。
enum VehicleIdentityDatabaseMigratorFactory {
    /// このバイナリが認識するMigration識別子です。
    static let knownMigrationIdentifiers = [VehicleIdentitySchema.v1MigrationIdentifier]

    /// ユーザースコープを初回schemaへ固定するMigratorを生成します。
    /// - Parameters:
    ///   - userScopeID: 専用DBが所有するユーザースコープUUID。
    ///   - activeDigestKeyVersion: 初回に利用するDigest鍵Version。
    ///   - createdAt: scopeメタデータの作成日時。
    /// - Returns: v1を一transactionで適用するMigrator。
    static func makeMigrator(
        userScopeID: UUID,
        activeDigestKeyVersion: Int,
        createdAt: Date
    ) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(VehicleIdentitySchema.v1MigrationIdentifier) { database in
            let version = try String.fetchOne(database, sql: "SELECT sqlite_version()") ?? "0"
            guard sqliteSupportsStrictTables(version) else {
                throw VehiclePersistenceError.unavailable
            }
            try database.execute(sql: VehicleIdentitySchema.v1SQL)
            try database.execute(
                sql: "INSERT INTO database_scope (scope_row_id, user_scope_id, active_digest_key_version, created_at) VALUES (1, ?, ?, ?)",
                arguments: [userScopeID.uuidString.lowercased(), activeDigestKeyVersion, GRDBVehicleDateCodec.string(from: createdAt)]
            )
            let foreignKeyFailures = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            guard foreignKeyFailures.isEmpty else {
                throw VehiclePersistenceError.unavailable
            }
        }
        return migrator
    }

    /// STRICT tableを利用できるSQLite 3.37.0以上か判定します。
    /// - Parameter version: `sqlite_version()`が返したdot区切り文字列。
    /// - Returns: 最低Version以上ならtrue。
    private static func sqliteSupportsStrictTables(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        let padded = parts + Array(repeating: 0, count: max(0, 3 - parts.count))
        return (padded[0], padded[1], padded[2]) >= (3, 37, 0)
    }
}
