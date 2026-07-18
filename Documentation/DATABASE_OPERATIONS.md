# Database Operations

## 保存方式の役割

| 保存方式 | 推奨用途 | 禁止事項 |
|---|---|---|
| SwiftData | Appleプラットフォーム中心の設定、編集対象、関係モデル | SwiftData `@Model` をViewやDomainへ公開しない |
| GRDB | 大量レコード、明示SQL、集計、ログ、厳密なMigrationが必要なデータ | SQLやGRDB RecordをData層外へ公開しない |

現在の `Item` はSwiftDataをSystem of Recordとします。Vehicle Identity StoreはGRDBをSystem of Recordとし、SwiftDataへ同じ車両、識別子、Scan、ECU観測、識別値を保存しません。GRDBは公式Swift Package `7.10.0` をexact versionで固定します。

## 必須台帳

新しい永続データを追加するときは、この表へ正本を追記します。

| データ | System of Record | Repository | 備考 |
|---|---|---|---|
| Item | SwiftData | `ItemRepository` | テンプレート機能。将来削除可能 |
| Vehicle | GRDB | `VehicleIdentityRepository` | 内部UUID、暗号化済み任意表示名、active／archived、field revision |
| Vehicle Identifier | GRDB | `VehicleIdentityRepository` | 暗号化済み正規化値とユーザー別Keyed Digest。平文は保存・公開しない |
| Vehicle Identification Scan | GRDB | `VehicleIdentityRepository` | 一OBD接続につき最終終端Snapshot一件。validは非NULL `vehicle_id` 必須 |
| ECU Observation | GRDB | `VehicleIdentityRepository` | Scan配下の追記専用ECU応答観測 |
| ECU Identification Value | GRDB | `VehicleIdentityRepository` | 暗号化済みDecoded Value／Raw Responseを含む追記専用識別値 |

## 変更ルール

1. 先にDomainモデルとRepository境界を定義する。
2. データごとにSwiftDataまたはGRDBの片方だけを正本にする。
3. スキーマ変更と同じ変更単位でMigrationとMigrationテストを追加する。
4. Migrationは追記方式とし、リリース済みMigrationを書き換えない。
5. 起動失敗時に既存DBを自動削除しない。エラーを保持し、安全な復旧導線を設計する。
6. SwiftDataとGRDBをまたぐ処理は、Applicationのユースケースで調停する。Adapter同士を直接呼ばない。
7. 大量データ処理ではUI actorを占有しない設計を別途行い、性能テスト条件を記録する。

## GRDB導入時に追加する構成

```text
Data/Persistence/GRDB/
├── Database/
│   ├── AppDatabase.swift
│   └── DatabaseMigratorFactory.swift
├── Migrations/
├── Records/
└── Repositories/
```

## Vehicle Identity Store v1

- Migration IDは `v1_create_vehicle_identity_store`。リリース後は編集、並べ替え、削除をせず、新しい変更理由ごとに追記する。
- `database_scope`、`vehicles`、`vehicle_identification_scans`、`vehicle_identifiers`、`ecu_observations`、`ecu_identification_values` を一transactionで作成する。
- 全業務テーブルはSTRICT tableであり、scope Trigger、複合Foreign Key、Unique制約、追記／物理削除拒否Triggerを持つ。
- Migration中のscope行作成、DDL、整合性検査のいずれかが失敗した場合はv1全体をrollbackする。既存DBを削除して再作成しない。
- 起動時に既知Migration ID、`database_scope`、`PRAGMA quick_check`、`PRAGMA foreign_key_check` を検査する。未知Version、scope不一致、破損、open失敗はランダム診断ID付きの明示的unavailable結果とし、元ファイルを保持する。
- down-migrationは行わない。旧バイナリで開けないschemaは機能を停止し、前方修正Migrationまたは整合したDBと対応鍵のバックアップ復元で回復する。
- commit結果不明の登録再試行は、Identifier Uniqueと `obd_connection_id` Uniqueに加え、暗号文を含む最終Snapshot全行が一致する場合だけ冪等成功とする。差異があればConflictとして既存行を保持する。
- 車両登録transactionとAcquisition Session binding transactionは別境界である。SessionのSystem of RecordとMigrationは未導入のため、Production binding実装は明示的unavailableのままとし、登録済みVehicle／Scanを削除しない。

暗号鍵取得、暗号化、Digest計算、Keychain、正規化方式はこのv1実装に含めません。Repositoryは事前準備・読戻し検証済みの不透明な暗号文、鍵Version、32 byte Digestだけを受け取ります。これらの仕様が確定してComposition Rootへ接続されるまで、Production車両登録はblockedを維持します。
