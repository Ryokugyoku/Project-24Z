import Foundation
import GRDB

/// ユーザー専用DatabasePoolとRepositoryを所有するGRDB Composition境界です。
final class GRDBVehicleIdentityStore {
    /// scope専用の車両Identity Repositoryです。
    let repository: GRDBVehicleIdentityRepository

    /// 同じscope専用DBを使うAcquisition Repositoryです。
    let acquisitionRepository: GRDBAcquisitionRepository

    /// Hard Gate後の通信と分離されたローカル同期台帳Repositoryです。
    let localSyncRepository: GRDBLocalSyncRepository

    /// テストと保全検査で共有するDatabasePoolです。
    let databasePool: DatabasePool

    /// 検査済みDatabasePoolからStoreを構成します。
    /// - Parameters:
    ///   - databasePool: scope専用でMigration済みのPool。
    ///   - userScopeID: Pool内の`database_scope`と一致するUUID。
    private init(databasePool: DatabasePool, userScopeID: UUID) {
        self.databasePool = databasePool
        repository = GRDBVehicleIdentityRepository(databasePool: databasePool, userScopeID: userScopeID)
        acquisitionRepository = GRDBAcquisitionRepository(databasePool: databasePool, userScopeID: userScopeID)
        localSyncRepository = GRDBLocalSyncRepository(databasePool: databasePool, userScopeID: userScopeID)
    }

    /// DBを非破壊で開き、未知Version、Migration、整合性、scopeを検査します。
    /// - Parameters:
    ///   - url: ユーザー別DBファイルURL。ファイル名に識別子を含めないこと。
    ///   - userScopeID: 期待する認証済みユーザースコープUUID。
    ///   - activeDigestKeyVersion: 空DBの初回Migrationに記録するDigest鍵Version。
    ///   - createdAt: 空DBのscope作成日時。
    /// - Returns: 利用可能Storeまたは元DBを保持した明示的unavailable結果。
    static func open(
        at url: URL,
        userScopeID: UUID,
        activeDigestKeyVersion: Int,
        createdAt: Date = Date()
    ) -> GRDBVehicleIdentityStoreOpenResult {
        guard activeDigestKeyVersion >= 1 else {
            return unavailable(.migrationFailed)
        }

        do {
            var configuration = Configuration()
            configuration.foreignKeysEnabled = true
            configuration.busyMode = .timeout(5)
            configuration.prepareDatabase { database in
                SyncChainDigestV1.register(in: database)
            }
            let pool = try DatabasePool(path: url.path, configuration: configuration)

            let applied = try pool.read { database -> [String] in
                guard try database.tableExists("grdb_migrations") else { return [] }
                return try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            }
            let unknown = Set(applied).subtracting(VehicleIdentityDatabaseMigratorFactory.knownMigrationIdentifiers)
            guard unknown.isEmpty else {
                return unavailable(.unknownVersion)
            }

            let migrator = VehicleIdentityDatabaseMigratorFactory.makeMigrator(
                userScopeID: userScopeID,
                activeDigestKeyVersion: activeDigestKeyVersion,
                createdAt: createdAt
            )
            try migrator.migrate(pool)

            let verification = try verifyStartup(databasePool: pool, expectedScopeID: userScopeID)
            guard verification == nil else {
                return unavailable(verification!)
            }
            return .available(GRDBVehicleIdentityStore(databasePool: pool, userScopeID: userScopeID))
        } catch let error as DatabaseError
            where error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB {
            return unavailable(.corrupted)
        } catch {
            return unavailable(.openFailed)
        }
    }

    /// 起動時のscope、quick check、Foreign Keyを検査します。
    /// - Parameters:
    ///   - databasePool: Migration適用済みのPool。
    ///   - expectedScopeID: 認証境界が期待するscope UUID。
    /// - Returns: 成功ならnil、非破壊停止理由があればその分類。
    private static func verifyStartup(
        databasePool: DatabasePool,
        expectedScopeID: UUID
    ) throws -> VehicleIdentityStoreUnavailable.Reason? {
        try databasePool.read { database in
            let quickCheck = try String.fetchAll(database, sql: "PRAGMA quick_check")
            guard quickCheck == ["ok"] else { return .corrupted }
            let foreignKeyFailures = try Row.fetchAll(database, sql: "PRAGMA foreign_key_check")
            guard foreignKeyFailures.isEmpty else { return .corrupted }
            let scope = try String.fetchOne(
                database,
                sql: "SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1"
            )
            guard scope == expectedScopeID.uuidString.lowercased() else { return .scopeMismatch }
            return nil
        }
    }

    /// 安定分類とランダム診断IDを持つunavailable結果を作ります。
    /// - Parameter reason: 機密情報を含まない停止理由。
    /// - Returns: 呼び出し側が明示表示できる結果。
    private static func unavailable(
        _ reason: VehicleIdentityStoreUnavailable.Reason
    ) -> GRDBVehicleIdentityStoreOpenResult {
        .unavailable(VehicleIdentityStoreUnavailable(diagnosticID: UUID(), reason: reason))
    }
}
