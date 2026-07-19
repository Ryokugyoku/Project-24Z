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
| Acquisition Session | GRDB | `AcquisitionRepository` | 未割当を許容し、車両所属は保存確定前に一度だけ確定 |
| PID / Raw CAN Stream | GRDB | `AcquisitionRepository` | 種別ごとに別Stream。実ログ本体は含めない |
| Clock Epoch / Gap | GRDB | `AcquisitionRepository` | 再起動境界と欠損を非補間で保持 |
| Immutable Chunk Catalog | GRDB | `AcquisitionRepository` | file SHA-256とcanonical目録SHA-256を別列で保持 |
| PID / Raw CAN Chunk Body | immutable file | `ImmutableChunkFileStore` | 準備済み不透明bytes。staging、同期、読戻し、atomic rename後に公開 |
| Storage Integrity Finding | GRDB | `AcquisitionRepository` | 孤立、欠落、隔離、再試行状態。自動削除しない |
| Local Device / Peer Sync State | GRDB | `LocalSyncRepository` | Identity公開メタデータ、Trust、Peer別Cursor。秘密鍵と平文鍵は含めない |
| Logical Sync Change / Delivery / Receipt | GRDB | `LocalSyncRepository` | Origin EnvelopeとOrigin Sequence／ChainをPeer別配送・受領から分離 |
| Vehicle Alias / Materialization / Conflict | GRDB | `LocalSyncRepository` | graph generation履歴、expected digest、競合・隔離を非破壊保持 |
| Session / Chunk Transfer Progress | GRDB + immutable staging/final file | `LocalSyncRepository` / `ImmutableChunkFileStore` | Segment進捗とDurable ACK条件。bytesはDBへ保存しない |
| 端末別Primary／Secondary既定Adapter候補 | GRDB | `DefaultAdapterRepository` | User Scope＋local device scope＋roleごとにActive最大1件。Endpoint Digestと非機密表示名を保持し、端末間同期しない |
| 確認済みAdapter Identity Binding | GRDB | `DefaultAdapterRepository` | 接続後の承認済みIdentity確認だけを追記。候補表示名やOS identifierをIdentity証拠にしない |

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

## Acquisition Store v2

- Migration IDは `v2_create_acquisition_storage`。v1へ追記し、既存Vehicle Identity行を変換・削除しない。
- Session、Stream、Epoch、Gap、Chunk目録、保全FindingはGRDB、ログ本体はimmutable fileを唯一のSystem of Recordとする。
- Chunk file SHA-256はfile bytesの同一性、`catalog_digest`は順序固定・長さ付きcanonical目録の同一性を検証し、相互に代用しない。
- Durable ACKはstaging write、file同期、全読戻し、atomic rename、親directory同期、最終読戻し、目録commit・再読戻しが全て成功した場合だけ返す。
- fileをDBより先に確定する。rename後のDB失敗は完全な孤立fileとして保持し、起動時照合対象にする。staging残存物は隔離し、自動削除しない。
- 容量不足では新規確定を拒否し、既存DB、Chunk、staging、鍵を自動削除しない。
- Compression／AEAD／Keychainは設計上のVersion付き上流境界であり、本Migrationとfile Adapterは準備済みの不透明bytesを受け取る。Fake入力による検証を実取得・暗号Production実装と扱わない。
- down-migrationは行わない。v2失敗はtransaction全体をrollbackし、既存v1行とChunk fileを保持する。旧binaryは未知schemaを利用不可として前方修正を待つ。

## Local Sync State v3

- Migration IDは `v3_create_local_sync_state`。v1／v2へ追記し、既存Vehicle、Session、Chunk目録とfileを変換・削除しない。
- 同期設計の18 STRICT table、Origin／Streamの0始まりSequence／Chain Trigger、Peer別Delivery／Receipt／Cursor、Alias graph generation、Materialization、Conflict／Quarantine、Chunk Transfer進捗をGRDBで保持する。
- 通常読取りは9つの `active_or_local_*` Viewを使用する。preparing／ready graphを公開せず、atomic切替前は旧active、commit後は新activeだけを返す。Identifierは単一基底SELECTのOR EXISTSでlocal／active inserted／active linkedを1行化する。
- `sync_chain_digest_v1` は全GRDB接続へ登録するVersion固定・型tag・長さ付きcanonical SHA-256関数である。未登録、直前Change欠落、digest不一致ではLogical ChangeをINSERTしない。
- Cursorはapplied／duplicate Receiptまたはacked Deliveryを確認した一件だけ進む。Conflict、Quarantine、Sequence穴、Chain不一致を越えない。
- Chunk Durable ACKは全Segment verified、file durable、cataloged、期待Chunk件数・総bytes一致に加え、TransferのSession／Stream／Sequence、全Chunk目録値、ciphertext／catalog digest、4 Format／Key Versionがactive-or-local業務目録と完全一致した場合だけ確定する。Session、Stream、Clock Epoch、Gap、Chunkを親子順に並べ、各Entity Version／Revisionを含めたcanonical Session ManifestをACK直前と冪等再実行時に再計算する。全Entityがlocalまたはactive graphのapplied Materializationとして公開対象で、親子関係が一致し、Session＋Chunkへ束縛されたWrapped Keyが存在することを要求する。保存済みACKはACK IDだけでなくPeer／Batch／Transfer／Session／Manifest／binding digestを再検査する。容量不足、staging残存、破損、不一致では既存DB／fileを削除せず停止する。
- down-migrationは行わない。v3失敗はschema transaction全体をrollbackし、v1／v2と既存fileを保持する。未知Migration、`quick_check`／`foreign_key_check`失敗は空DBへFallbackせず利用不可とする。
- Membership Credential、Bootstrap、鍵共有、TLS Identity、SAS、canonical network codec、Network.framework通信は未確定Hard Gateである。v3 Migrationはローカル台帳を作るが、ProductionのMembership established化、Pairing、送受信を提供しない。テストのestablished Peer／codecはFake fixtureでありProduction証拠ではない。

## Local Sync State v4 hardening

- Migration IDは `v4_harden_sync_state_machines`。適用済みの `v3_create_local_sync_state` を書き換えず、Session Transfer、Chunk Transfer、Segment、Wrapped Keyへ正規UPDATE遷移のstep列とTriggerを追記する。
- 新規INSERTはそれぞれ `manifest_pending`、`pending`、`expected`、`received` だけを許可する。旧v3の途中／終端行は削除・推測補正せずstep 0のまま保持し、正規遷移来歴を証明できないためDurable ACK対象から隔離する。
- `origin_entity_materializations` はINSERT後、状態、適用時刻、superseded参照、監査用updated／revision列以外を変更できない。Origin、Alias、generation、親子、canonical Vehicle、Entity／materialized ID、projection情報の変更はDB Triggerが拒否する。
- down-migrationは行わない。v4失敗はALTER／Trigger追加transaction全体をrollbackし、旧v3業務行、Migration記録、外部Chunk fileを保持する。

## Connection Settings v5

- Migration IDは `v5_create_connection_settings`。v1からv4へ追記し、既存Vehicle、Session、Chunk、同期台帳、外部fileを変換・削除しない。
- `default_adapter_candidates` はUser Scope、local device scope、Platform、固定role、32 byte Endpoint Digest、非機密表示名、Transport種別、Revision、監査日時を保持する。OS identifier、MAC address、USB serial、Raw advertisementは通常表示列へ保存しない。
- partial unique indexにより端末scope／roleごとのActive候補を最大1件、端末scope内の同一Endpoint DigestをActive最大1件に制限する。通常変更は旧行を明示deactivateして新監査行をINSERTし、解除でも物理削除しない。
- `verified_adapter_bindings` は接続後に確認したAdapterReferenceのSHA-256 Digest、確認規則Version、確認日時をActive候補へ追記する。Identity不明値を保存するNULL状態は持たず、一候補一bindingと、現在Activeな役割間の物理参照一意Triggerを適用する。解除済み履歴は保持し、明示再選択後の再確認を永久に妨げない。
- 候補とbindingは過去Acquisition SessionへForeign Keyまたはcascadeを持たず、設定変更・解除で過去Session、Stream、Gap、Chunk、Vehicleを更新・削除しない。
- v5 Migration失敗はDDL全体をrollbackし、既存v1からv4のschemaと業務行を保持する。down-migration、既存DB削除、空DB Fallbackは行わない。
- 認証済みUser Scope、承認済みlocal device scope、正式対応Adapter／firmware／TransportのHard GateがComposition Rootへ接続されるまで、Production Repositoryは明示的unavailableとし、架空scopeのGRDBを作成しない。

## Development Database Browser read-only運用

- `PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER` 専用compile flagがある構成だけに型、Navigation、表示文字列、Adapterを含める。通常DebugとApp Store提出用Releaseではflagを定義しない。
- GRDBは起動時検査済み`DatabasePool`のread closureだけを使用し、`sqlite_schema`から`sqlite_%`を除くApplication tableを動的列挙する。直前の列挙結果と一致しないtable名は拒否し、任意SQL、write、Migration、修復、ATTACH、Exportを公開しない。
- SwiftDataは`Item`をSwiftData API経由の明示論理データセットとして読み、内部SQLiteを直接openしない。
- pageは最大500行の短いread単位とし、NULL、TEXT、INTEGER、REAL、BLOBを区別する。BLOBは推測Decodeや復号をせず、Chunk file、Keychain、秘密鍵へアクセスしない。
- `Scripts/validate_development_database_browser_boundary.sh`でApp Store向けmacOS／iOS Simulator Release binaryに開発専用symbol／表示文字列が残らないことを検査する。
