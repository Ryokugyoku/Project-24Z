# Database Operations

## 保存方式の役割

| 保存方式 | 推奨用途 | 禁止事項 |
|---|---|---|
| SwiftData | Appleプラットフォーム中心の設定、編集対象、関係モデル | SwiftData `@Model` をViewやDomainへ公開しない |
| GRDB | 大量レコード、明示SQL、集計、ログ、厳密なMigrationが必要なデータ | SQLやGRDB RecordをData層外へ公開しない |

現在の `Item` はSwiftDataをSystem of Recordとします。GRDBは未導入であり、依存パッケージもまだ追加しません。

## 必須台帳

新しい永続データを追加するときは、この表へ正本を追記します。

| データ | System of Record | Repository | 備考 |
|---|---|---|---|
| Item | SwiftData | `ItemRepository` | テンプレート機能。将来削除可能 |

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

導入時はGRDB公式パッケージをXcode Package Dependenciesへ追加し、バージョンを固定します。実データ向けに実装するまでは、空のDBや未使用テーブルを作りません。
