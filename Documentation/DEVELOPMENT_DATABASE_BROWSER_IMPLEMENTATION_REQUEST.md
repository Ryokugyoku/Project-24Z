# 開発専用データベース閲覧画面 実装製造依頼書

## 1. 文書状態

- Product decision status: 承認済み
- 対象Version: Development Database Browser Version 1
- 承認日: 2026-07-18
- 製品優先度: 接続設定・PID取得保存の実機検証補助
- 対象Platform: iOS、macOS
- 配布境界: Development buildおよび承認済みTestFlight buildで利用可能。App Store提出用Production buildでは除外
- 関連製造依頼: `CONNECTION_SETTINGS_IMPLEMENTATION_REQUEST.md`
- 正本運用文書: `DATABASE_OPERATIONS.md`

本書は、接続設定、車両登録、PID／Raw CAN取得・保存を実機で検証するとき、現在の端末へ実際に登録されたApplicationデータを読取専用で確認する開発画面を定義します。

この画面は製品機能、一般利用者向け管理画面、DB修復画面、任意SQL Clientではありません。実機検証のため承認済みTestFlight binaryへ含められますが、App Store提出用Production binaryでは除外します。データの編集、削除、復号、Export、Migration、修復を行いません。

## 2. 目的

開発者が実機上で次を確認できるようにします。

1. 現在のApplication GRDBに存在する全Application tableを一覧できる。
2. 選択したtableの全列と全行へ到達できる。
3. 接続設定、車両、Session、Stream、Gap、Chunk目録、同期状態等が期待どおり登録されたか確認できる。
4. NULL、TEXT、INTEGER、REAL、BLOBを保存時の型と値を失わず区別できる。
5. iOSとmacOSで、それぞれ独立した簡素な閲覧画面を使用できる。
6. 行数や列数が表示領域を超えても、table領域内の縦横スクロールで確認できる。
7. 大量行や大きなBLOBを全件一括メモリ展開せず、実機取得・保存処理を不必要に阻害しない。

## 3. データソース境界

### 3.1 GRDB

現在の認証済みUser Scopeへ割り当てられ、起動時保全検査に成功したApplication GRDBを対象にします。

- `sqlite_schema`から`type = 'table'`のtableを動的に列挙します。
- `sqlite_%`で始まるSQLite内部table／shadow tableは対象外です。
- `grdb_migrations`はMigration確認に必要なため対象へ含めます。
- 現在存在するApplication tableと、将来の承認済みMigrationで追加されるApplication tableを固定配列へ重複記載せず自動列挙します。
- TEMP table、別processの一時DB、staging file、quarantine fileをApplication tableとして混在させません。
- SQL View、Trigger、Indexは「table情報をすべて表示する」Version 1の対象外です。将来必要になった場合は別カテゴリとして追加します。

選択したGRDB tableは、実際の列名、SQLite storage class、NULL、保存値を読取専用で表示します。業務Repositoryの通常Viewへ投影した結果へ置き換えず、開発検証対象の物理table行を表示します。

### 3.2 SwiftData

現在の`Item`はSwiftDataをSystem of Recordとします。SwiftDataの内部SQLite SchemaはApplication契約ではないため、store fileをGRDB／SQLiteで直接openしません。

- `Item`をSwiftData API経由の論理データセットとして一覧へ含めます。
- データソース名を`SwiftData`、データセット名を`Item`としてGRDB tableと区別します。
- SwiftDataが公開するApplication model propertyだけを列として表示します。
- SwiftData内部table名、内部Foreign Key、内部Metadataを「実table」として保証しません。
- 将来SwiftData modelが増えた場合、自動reflectionで推測追加せず、Application modelごとの読取Adapterを明示追加します。

SwiftData内部物理tableそのものを確認する要件が生じた場合は、Appleの互換性、live store locking、破損リスクを検証した別の開発Tool要件とします。

### 3.3 DB外データ

PID／Raw CAN Chunk本体はimmutable fileがSystem of Recordであり、DB tableではありません。

- `log_chunks`等の目録行と保存されているrelative pathは表示します。
- Chunk fileの開封、復号、展開、Raw PID／CAN Payload表示は行いません。
- Keychain、秘密鍵、平文対称鍵、TLS Identityを表示しません。
- quarantine／staging fileの内容を表示しません。

## 4. Development限定境界

### 4.1 Compile-time Gate

- 画面、Application Model、Development Repository Adapter、Navigation destination、表示文字列を専用compile conditionで囲みます。
- `DEBUG`の有無だけに依存せず、専用フラグ`PROJECT24Z_DEVELOPMENT_DATABASE_BROWSER`を有効化の必須条件とします。
- Development用実機構成と、実データ検証を行う承認済みTestFlight archive構成で同フラグを有効化できます。
- App Store提出用Production archive構成では同フラグを無効化し、型、文字列、Navigation destination、symbolがbinaryへ残らないことを検査します。
- 通常のApp Store向けComposition RootからDevelopment Browserを生成できません。専用フラグ有効時だけ、実際の認証済みProduction相当Storeへread-only依存を追加します。
- Development Browserを有効にするためProduction接続、認証、DB scope検証をFakeへ差し替えません。
- TestFlight buildに含まれる場合も、利用者のProductionデータを編集できる能力へ拡張しません。

実データ確認用Development buildと、Preview／UI Testのfixture buildは別の証拠です。fixture表示成功を実端末DB閲覧済みと報告しません。

### 4.2 Entry Point

- 設定画面にDevelopment専用Sectionを追加します。
- 項目名は「データベース閲覧」とします。
- 選択するとiOS／macOSそれぞれの独立した別画面へ遷移します。
- 通常の接続設定、車両管理、ダッシュボードへtable selectorや行表示を埋め込みません。
- Compile-time Gate無効時はSection自体を表示しません。

### 4.3 注意表示

- 初回表示時に「開発専用」「実データを表示する」「編集・削除はできない」ことを表示します。
- 画面全体をprivacy sensitiveとして扱い、Application switcher等でOS標準の保護が利用できる範囲は適用します。
- VIN、車台番号、Raw Payload等を復号して表示しないため、暗号化列は保存済みciphertextのままです。
- 画面表示内容をTelemetry、analytics、通常ログ、Crash annotationへ送信しません。

## 5. 画面要件

### 5.1 共通構成

画面は最低限、次で構成します。

1. データソース選択
2. table／データセット選択
3. 選択対象名
4. 列数
5. 現在確認できた総行数
6. 最終読込日時
7. 手動更新Action
8. table header
9. 行データ領域
10. 読込中／空／利用不可／失敗状態

データソースが一つしかない場合もApplication Stateにはsourceを保持し、View都合でGRDBとSwiftDataを同じtableとして偽装しません。

### 5.2 Selector

- データソースはPull-down／Pickerで`GRDB`または`SwiftData`を選択します。
- GRDB選択時は、別のPull-down／Pickerに全対象tableを名前順で表示します。
- SwiftData選択時は、別のPull-down／Pickerに明示対応済みデータセットを表示します。
- 前回選択をprocess中に保持できますが、製品設定として永続化する必要はありません。
- Migration後に存在しないtable名を復元せず、一覧を再取得して未選択状態へ戻します。
- table名を利用者入力の任意SQL identifierとして受け付けません。

### 5.3 Table領域

- 列headerを先頭に表示します。
- 行は縦方向へスクロールできます。
- 全列は横方向へスクロールできます。
- 画面全体ではなく、table表示領域内で縦横スクロールします。
- 最低列幅を設け、値が表示幅を超えても隣接列を押し潰しません。
- cellの表示を省略する場合も、cell詳細を開くと保存値全体へ到達できます。
- 行番号は表示用であり、DBのPrimary Keyまたは`rowid`として扱いません。
- Primary Key列を視覚的に区別できますが、業務上の意味を推測表示しません。
- 空tableはheaderを維持し、「0件」と表示します。

### 5.4 iOS

- iOS専用Viewを`Platform/iOS`へ置きます。
- source／table selectorを画面上部へ配置します。
- table領域は縦横スクロール可能なGrid相当の簡素な表示にします。
- cell選択で、列名、storage class、NULL状態、完全な値を別sheetまたはdetailへ表示します。
- Dynamic Typeでheaderと操作領域を読めるようにし、table cellの最小幅を無制限に縮めません。
- VoiceOverでtable名、行番号、列名、値の型、NULLを識別できるLabelを提供します。

### 5.5 macOS

- macOS専用Viewを`Platform/macOS`へ置きます。
- source／table selectorをtoolbarまたは画面上部へ配置します。
- table領域は縦横スクロール可能なmacOS向けTable／Grid相当の簡素な表示にします。
- 列幅変更を許可できますが、列幅をApplication StateやDBへ保存しません。
- cell選択で完全な値をdetailまたはsheetへ表示します。
- Keyboard、Focus、VoiceOverでselector、更新、table、cell詳細を操作できます。

iOSとmacOSで同じView、巨大なPlatform条件分岐View、共有レイアウトを使用しません。共有できるのはApplication State、読取Action、表示専用値だけです。

## 6. 値の表示規則

SQLite／SwiftDataの値を次のように区別します。

| 値 | cell表示 | 詳細表示 |
|---|---|---|
| NULL | `NULL` | NULLであることを明示 |
| TEXT | 先頭の表示可能範囲 | 保存文字列全体。改行・制御文字の存在を区別 |
| INTEGER | 10進文字列 | 符号付き値全体 |
| REAL | 精度を失わない変換 | 保存値を再現可能な文字列表現 |
| BLOB | `BLOB · <byte count>` | 全byteの16進表現を縦横スクロール表示 |
| SwiftData値 | 型に応じた値 | Application model propertyの完全な値 |

- NULLを空文字、0、false、空BLOBへ変換しません。
- BLOBをUTF-8、UUID、暗号文、Digest、画像等へ推測Decodeしません。
- 暗号化列を復号しません。
- 日時TEXTを端末Locale表示へ置換せず、保存値を表示します。
- BLOB詳細は全byteへ到達可能にしますが、table一覧では展開しません。
- 巨大TEXT／BLOB詳細も一括で通常cellへ展開せず、専用detailで表示します。
- 通常画面へcopy、share、Export Actionを追加しません。

## 7. 全行閲覧と性能

「すべて表示」は、対象tableの全行へスクロールで到達できることを意味し、全行を一度にメモリへ展開することを意味しません。

- 内部では固定上限付きpageを順次読み込みます。
- page sizeは技術測定で決め、製品仕様値を推測固定しません。
- Primary Keyまたは一意な安定順序が利用できる場合はkeyset paginationを優先します。
- rowid tableでPrimary Key順序が使えない場合はrowidを候補にできます。
- WITHOUT ROWIDかつ安定したkeysetを組めないtableでは、安全にquoteした列順序またはLIMIT／OFFSET fallbackを使用し、順序保証の限界を画面状態へ公開します。
- 同じ行を隠す重複排除や業務Filterを適用しません。
- page境界のために行を省略せず、末尾まで到達したことを状態として保持します。
- 一回の長時間read transactionを保持しません。
- 自動refresh／pollingを行わず、利用者の手動更新を基本とします。
- 更新中tableではpage間に行が変化し得ることを表示し、厳密Snapshotを捏造しません。
- 取得中に閲覧してもDB write、Adapter callback、保存queue、UI actorを長時間blockしないよう、読取をData層の専用非UI executorで行います。
- memory warning、取消し、別table選択時は不要pageとdetail byte bufferを解放します。

## 8. Read-only保証

- Development Browser用protocolにINSERT、UPDATE、DELETE、DDL、Migration、VACUUM、REINDEX、ATTACH、PRAGMA write操作を置きません。
- 任意SQL入力欄を設けません。
- GRDBは既存の起動時検査済みDatabasePoolから読取専用closureで取得します。
- Browser表示のためにDBを新規作成、Migration、修復、削除しません。
- DB unavailable、unknown Migration、scope不一致、`quick_check`／`foreign_key_check`失敗時は元ファイルを保持し、利用不可理由だけを表示します。
- SwiftDataはfetch専用境界を使用し、ModelContextのinsert、delete、saveを公開しません。
- cell選択、scroll、refreshでデータを変更しないことをテストします。
- TriggerやLast Access列等の副作用がある独自読取を追加しません。

## 9. Schema Discoveryの安全条件

- table一覧は固定SQLで`sqlite_schema`を読み取ります。
- 選択table名は直前のschema discovery結果と完全一致するものだけを受理します。
- identifierはGRDB／SQLiteの安全なidentifier quoting境界を通し、文字列連結した任意SQLを生成しません。
- 列情報は`PRAGMA table_xinfo`相当の固定境界から取得します。
- Primary Key順序、hidden／generated column、WITHOUT ROWIDを識別します。
- hidden／generated columnをtable列として返す場合は種別を表示し、通常列と偽装しません。
- schema変更を検出した場合は現在pageを破棄し、table／column metadataを再読込します。
- 未知SQLite storage classや読取不能値を空文字へ変換せず、安定Errorとして表示します。

## 10. Application StateとAction

Applicationは最低限、次をPlatformへ公開します。

### 10.1 State

- 利用可能なデータソース
- 選択中データソース
- 利用可能なtable／データセット
- 選択中table／データセット
- column metadata
- row count
- 読込済みpageと行表示値
- 次pageの有無
- 読込状態
- 最終更新日時
- DB unavailable／scope mismatch／schema changed／read failed等の安定Error
- cell詳細

Stateへ画面幅、列pixel幅、scroll offset、sheet高さ、NavigationSplitView選択等のレイアウト値を持ち込みません。

### 10.2 Action

- sourceを選択
- table／データセットを選択
- 最初のpageを読込
- 次pageを読込
- 手動更新
- 読込取消し
- cell詳細を開く
- cell詳細を閉じる

編集、削除、SQL実行、Export、復号、file open Actionは公開しません。

## 11. 配置と依存方向

| 層 | 責務 |
|---|---|
| Domain | Development Browserが必要とする純粋なsource／table／column／cell値と読取protocol。Development compile gate内 |
| Application/DevelopmentDatabaseBrowser | schema、paging、選択、refresh、cell詳細の状態調停 |
| Data/Persistence/GRDB/Development | GRDB schema discoveryとpage readの具象Adapter |
| Data/Persistence/SwiftData/Development | 明示SwiftData modelのread-only Adapter |
| Platform/iOS/Development | iOS専用Database Browser View |
| Platform/macOS/Development | macOS専用Database Browser View |
| App/Development | Development flag有効時だけ依存生成とNavigation注入 |

依存方向は`Platform -> Application -> Domain <- Data`を維持します。ViewからGRDB、DatabasePool、ModelContext、SQL、fileを直接操作しません。

新規・変更Swift宣言、initializer、メソッド、privateメソッドへSwift DocCを付けます。Development専用型であってもDocC、Source Quality、依存方向検査を免除しません。

## 12. 必須画面状態

- 初回注意表示
- データソース未選択
- table未選択
- schema読込中
- table一覧取得済み
- table読込中
- 0行
- 1page表示
- 複数page表示／次page読込中
- 全行到達
- cell詳細表示
- 手動更新中
- 更新中で一貫Snapshotを保証しない状態
- schema変更検出
- GRDB unavailable
- SwiftData unavailable
- User Scope不一致
- read失敗
- 読込取消し
- Development Browser flag無効。App Store向け通常binaryでは画面自体が存在しない

## 13. 必須テスト

### 13.1 配布境界

- 専用compile flagなしのDebug buildで画面とNavigationが存在しない。
- 専用compile flagありのDevelopment buildで画面とNavigationが存在する。
- 承認済みTestFlight archiveで画面とNavigationが存在し、実Storeのread-only依存へ接続される。
- App Store提出用macOS Production buildに画面型、表示文字列、Navigation、symbolが存在しない。
- App Store提出用iOS Production buildに同じDevelopment artifactが存在しない。
- TestFlight用archiveとApp Store提出用archiveのflagを同じ曖昧なRelease設定へ依存させず、構成またはCI入力で明示的に分離する。
- 既存`validate_release_fixture_boundary.sh`と同等以上の専用検査で、App Store提出用binaryへの残存を拒否する。

### 13.2 Schema／Data

- `sqlite_%`内部tableを除外する。
- `grdb_migrations`と全Application tableを列挙する。
- 将来Migrationで追加したtableが固定一覧変更なしに表示される。
- GRDBとSwiftData sourceを混同しない。
- NULL、空TEXT、0、false相当INTEGER、空BLOBを区別する。
- TEXT、INTEGER、REAL、BLOBの完全値へcell詳細から到達できる。
- BLOBを推測Decodeまたは復号しない。
- hidden／generated column、composite Primary Key、WITHOUT ROWIDを安全に扱う。
- 悪意あるtable／column名相当fixtureでidentifier injectionが成立しない。
- scope不一致、unknown Migration、破損DBを新規DBへFallbackしない。

### 13.3 Paging／Concurrency

- 0行、1行、page境界、複数page、最終pageを確認する。
- 全行が一度ずつ到達可能で、意図的なFilter／truncateがない。
- table切替、source切替、refresh、取消し後のstale callbackを表示へ適用しない。
- 大量行でUI actorを長時間blockしない。
- 大きなTEXT／BLOBを一覧cellへ全展開しない。
- 長時間read transactionを保持しない。
- 取得中の追加行について厳密Snapshotと誤表示しない。

### 13.4 Read-only

- 全公開ActionにDB write能力がない。
- 一覧、scroll、次page、refresh、cell詳細の前後でDB digest／行数／RevisionがBrowser由来で変化しない。
- SwiftDataのinsert、delete、saveがBrowser経路から呼べない。
- 任意SQL、編集、削除、Export、復号、Chunk file open UIが存在しない。

### 13.5 Platform

- iOSとmacOSを別Viewツリーで確認する。
- sourceとtableをPull-down／Pickerで切り替えられる。
- table領域内で縦横スクロールできる。
- 画面幅を超える列と行数を確認できる。
- cell詳細で省略前の完全な保存値を確認できる。
- Dynamic Type、VoiceOver、Keyboard、Focusを対象Platformで確認する。
- 実機Development buildで実GRDB行を表示し、fixture表示と証拠を分離する。

## 14. 初期版対象外

- App Store提出用Production buildへの搭載
- DB編集、削除、追加、修復、Migration実行
- 任意SQL Console
- CSV、JSON、SQLite、Clipboard、Share SheetへのExport
- Keychain、秘密鍵、平文対称鍵、TLS Identity表示
- 暗号化列の復号
- Chunk／staging／quarantine fileの内容表示
- PID／Raw CAN Payloadのfileからの展開表示
- SQL View、Trigger、Indexの一覧表示
- SQLite内部table／shadow table表示
- SwiftData内部SQLite storeの直接open
- Remote端末、別User Scope、同期先DBの閲覧
- 自動refresh、監視、更新通知による常時Query
- DB内容を通常ログ、Telemetry、analyticsへ送信

## 15. 検証と証拠の区分

| 証拠 | 証明できる範囲 |
|---|---|
| Unit test | schema discovery、値変換、paging、read-only Action、stale拒否 |
| Fixture／Preview | iOS／macOS表示状態。実DBを証明しない |
| Simulator | 対象Simulator storeの表示。実端末データを証明しない |
| macOS Development build | 対象Macの実Application DB表示 |
| iPhone Development build | 対象iPhoneの実Application DB表示 |
| TestFlight binary inspection | 承認済みTestFlight buildにBrowserが含まれ、実Storeのread-only境界へ接続されていること |
| App Store binary inspection | BrowserがApp Store提出用Production buildへ残らないこと |
| ユーザー目視確認 | 縦横scroll、table切替、全値到達性、最終レイアウト確認 |

build成功だけで全table／全行表示、実端末DB、TestFlight搭載、App Store build除外、読取専用を証明済みと報告しません。

## 16. 製造担当の完了報告

1. 追加したDevelopment compile flagと有効な構成。
2. 対応したGRDB source、SwiftDataデータセット、除外対象。
3. 表示できたtable数、代表table、0行／大量行／BLOBの検証結果。
4. iOS／macOSの別画面確認。
5. 実機Development DBとfixture／Simulatorを分離した証拠。
6. 承認済みTestFlight binaryにDevelopment Browserが含まれることと、App Store提出用Production binaryから除外されたことの検査結果。
7. Browser操作によるDB変更がないことの検証結果。
8. 未検証事項、性能上限、既知の順序保証限界。

Development BrowserのためにProduction DBを削除、複製、Migration、復号、Exportしたり、通常Repositoryの安全条件を緩めたりしません。
