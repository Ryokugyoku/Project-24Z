# GRDB boundary

Vehicle Identity StoreのDatabase、Version付きMigration、Repository実装を配置します。GRDB固有型とSQLはこのData境界の外へ公開しません。System of Record、v1 Migration、非破壊復旧は `Documentation/DATABASE_OPERATIONS.md` に従います。
