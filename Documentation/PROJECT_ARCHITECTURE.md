# Project 24Z アーキテクチャ・コーディング規約

> 状態: 正式採用 v1.1
>
> 対象: iOS / macOS 共通製品
>
> 適用開始日: 2026-07-19
>
> 目的: 製造工程と同じ感覚で、責任範囲、入出力、異常時の停止位置を追跡できるプロジェクトにする。

## 1. 設計思想

Project 24Zは、ソフトウェアを一つの大きな装置としてではなく、責任が分かれた製造ラインとして設計します。

各工程は、前工程から決められた形式で入力を受け取り、担当する加工だけを行い、検査可能な形式で次工程へ渡します。工程をまたいで内部部品を直接操作しません。これにより、不具合が起きたときに「どの工程の問題か」「入力が悪いのか、加工が悪いのか、設備が悪いのか」を切り分けられます。

| ソフトウェア上の層 | 製造現場での役割 | 責任 |
|---|---|---|
| `Platform` | 操作盤・表示器 | 利用者への表示と入力受付 |
| `Application` | 工程表・作業指示・工程制御 | 処理順序、状態遷移、異常時の分岐 |
| `Domain` | 製品仕様・判定基準・図面 | 業務上の値、成立条件、設備インターフェース仕様 |
| `Data` | 加工設備・検査器・倉庫・搬送設備 | DB、ファイル、通信、暗号などの具体処理 |
| `App` | ライン立上げ・設備結線 | 実装を選び、各工程を接続し、生存期間を管理 |
| `Shared` | 共通の表示資材 | 色、文字、画像、ローカライズなど非業務資産 |

最重要原則は次の一文です。

> 上流工程は下流設備の具体方式を知らず、契約された入力・出力だけを知る。

## 2. 現在のフォルダ構成

現在の構造は次の通りです。

```text
Project 24Z/
├── App/                         # 起動、依存生成、iOS/macOSルート選択
├── Application/<Feature>/       # 機能単位の工程制御
├── Domain/
│   ├── Models/                  # 業務上の値と結果
│   ├── Repositories/            # 外部設備に要求する能力
│   └── Services/                # 外部I/Oを持たない判定・計算
├── Data/
│   ├── Communication/           # ELM、USB、通信Adapter
│   ├── FileSystem/              # ファイル操作
│   ├── Networking/              # ネットワーク実装
│   ├── Persistence/             # SwiftData、GRDB
│   ├── Security/                # Keychain、暗号処理
│   └── VehicleIdentification/   # 車両識別の具体検証
├── Platform/
│   ├── iOS/                     # iOS専用Viewと画面遷移
│   └── macOS/                   # macOS専用Viewと画面遷移
├── Shared/                      # レイアウトを持たない共通表示資産
└── Assets.xcassets

Project 24ZTests/                # Domain/Application/Dataの単体テスト
Project 24ZUITests/              # 必要な場合だけ置くプラットフォーム別UIテスト
```

## 3. 依存関係

許可する依存方向は次の通りです。

```text
Platform ──> Application ──> Domain
                               ^
                               │
Data ──────────────────────────┘

App ──> Platform / Application / Domain / Data
Shared ──> 業務ロジックを持たない表示資産のみ
```

- `Domain` は他の製品層へ依存しません。
- `Application` は `Domain` の型と能力契約を使います。具体的なDB、USB、ELM、Keychainを知りません。
- `Data` は `Domain` が定義した能力契約を実装します。画面や画面状態を知りません。
- `Platform` は `Application` が公開した状態を表示し、操作を通知します。
- `App` だけが具象実装を生成して接続します。
- `Shared` は便利機能の逃げ場にしません。

依存関係に迷った場合は、「その型は設備を交換しても同じ意味か」で判断します。同じ意味なら `Domain` または `Application`、設備固有なら `Data`、操作盤固有なら `Platform` です。

## 4. 標準の処理フロー

### 4.1 利用者操作

```text
利用者
  -> Platformが入力を受ける
  -> ApplicationへActionを通知する
  -> Applicationが工程順序を制御する
  -> Domainの判定または能力契約を呼ぶ
  -> Dataが具体処理を行う
  -> Domainの結果として返す
  -> Applicationが表示状態を更新する
  -> Platformが再描画する
```

Viewは、DBや通信設備を直接操作しません。操作盤から倉庫や加工機を直接動かさず、必ず工程制御を通す考え方です。

### 4.2 起動と依存組立

`App/Project24ZProductionComposition.swift` をComposition Rootとします。

- Productionで使う具体実装を選ぶ。
- インスタンスの生存期間を決める。
- `Domain` の能力契約へ `Data` の実装を接続する。

Composition Rootに業務判断やデータ変換は置きません。結線図として読める状態を維持します。

## 5. 各層の責任

### Domain: 製品仕様と合否基準

置くもの:

- ID、時刻、計測値、状態、結果などの業務上の値
- 外部I/Oを使わない判定・計算
- 保存、通信、暗号などに必要な「能力」のprotocol
- 業務として区別すべき失敗型

置かないもの:

- SwiftUI、UIKit、AppKit
- SwiftData、GRDB、SQL、FileManager、URLSession
- 画面文言、余白、色、ナビゲーション
- 特定Adapterや特定DBの都合

### Application: 工程制御

置くもの:

- Use Case、Coordinator、画面Model
- 操作の順序、状態遷移、取消し、再試行、縮退判断
- Domainの結果から表示状態への変換
- 非同期処理の所有者とstale結果の拒否

置かないもの:

- SQL、ファイル書込み、USB bytes、HTTP request
- SwiftUI View
- 具体RepositoryやAdapterの生成
- 画面幅やプラットフォーム固有レイアウト

### Data: 設備実装

置くもの:

- SwiftData / GRDB Repository
- ファイル、暗号、Keychain
- USB、ELM、ネットワーク通信
- Domain型と設備固有型の相互変換
- Migrationと設備固有エラーのDomainエラーへの変換

Data実装は、入力、出力、副作用、失敗条件が単体で確認できる大きさにします。

### Platform: 操作盤

置くもの:

- SwiftUI View
- プラットフォーム固有の画面階層、Navigation、Toolbar、Window
- 表示だけに必要な軽量な書式設定
- 利用者操作のApplicationへの通知

iOSとmacOSは同じ情報を扱っても別の操作盤です。Viewツリーを共有せず、それぞれの標準UIと利用可能領域に合わせます。共有するのはApplication状態とレイアウトを持たない資産だけです。

### App: ライン立上げ

置くもの:

- `@main`
- Production / Debug Fixtureの依存組立
- iOS / macOSのルート選択
- アプリ全体と同じ寿命を持つ依存の保持

## 6. ファイル配置の判断表

| 作るもの | 配置 |
|---|---|
| 業務上の値、状態、結果 | `Domain/Models` |
| 純粋な判定や計算 | `Domain/Services` |
| DB・通信・暗号などへ要求する能力 | `Domain/Repositories` |
| 処理順序、状態遷移、Use Case | `Application/<Feature>` |
| SwiftData / GRDB / File / USB / ELM / Keychain実装 | `Data/<Technology or Responsibility>` |
| iOS画面 | `Platform/iOS` |
| macOS画面 | `Platform/macOS` |
| 依存生成 | `App` |
| 色、文字、画像、Localization | `Shared` またはAsset Catalog |

新機能は、必要な層にだけ同じFeature名で追加します。全層へ機械的に空ファイルを作りません。

## 7. コーディング規約

### 7.1 型とファイル

- 単一責任の原則（Single Responsibility Principle）を採用する。型とメソッドは、それぞれ一つの理由でだけ変更される状態を保つ。
- 型の責任は「何を受け取り、何を決定または生成する型か」を一文で説明できなければならない。
- メソッドは一つの結果だけを作り、同じ抽象度の処理だけを扱う。工程制御、業務判定、永続化、表示変換を一つのメソッドへ混在させない。
- 責任の説明に、独立した二つの目的を「および」「さらに」で連結する必要がある場合は、型またはメソッドの分割を検討する。
- 型が別の層の変更理由を持ち始めた場合は、層境界のprotocolと実装へ分離する。
- 1ファイルには、検索時の主役となる型を原則1つ置く。
- 分割基準は行数ではなく「変更理由が複数あるか」とする。
- 小さな専用Error、補助enum、private型は主役と同じファイルに置いてよい。

単一責任は「メソッドを短くすること」や「ファイルを細かく分けること」そのものではありません。責任、入力、出力、変更理由が一つの工程として説明できることを合格基準とします。

### 7.2 命名規則

命名はSwift公式の[API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)に準拠します。最優先事項は呼出箇所での明瞭さです。文字数を減らすことより、利用側のコードだけで意図を誤解なく読めることを優先します。

#### 大文字・小文字

| 対象 | 形式 | 例 |
|---|---|---|
| class、struct、actor、enum、protocol、typealias | `UpperCamelCase` | `VehicleIdentity`, `ConnectionRuntime` |
| function、method、property、local variable、parameter | `lowerCamelCase` | `startSession`, `vehicleID` |
| enum case | `lowerCamelCase` | `.awaitingConfirmation` |
| generic type parameter | `UpperCamelCase` | `Element`, `Repository` |

- ソースコードのidentifierは英語にする。画面表示文言はLocalization資産へ置く。
- 一般に大文字で表す頭字語は、単語の一部として一貫して扱う。型では`URLSession`、値では`urlSession`のようにする。
- `ID`、`URL`、`USB`、`OBD`、`CAN`、`PID`、`ECU`など、分野で意味が確立した略語は使用できる。
- 独自略語、チーム内だけで通じる省略、1文字名は避ける。短いclosureや数式の局所変数だけは例外とする。
- 単位を持つ数値は、型または名前で単位を明示する。例: `timeoutSeconds`, `byteCount`, `sampleInterval`。

#### 責任別の型名

| 責任 | 名前の例 |
|---|---|
| 業務上の値 | `VehicleIdentity`, `AcquisitionSession` |
| 画面状態と操作 | `VehicleRegistrationModel` |
| 単一工程 | `PersistAcquisitionChunkUseCase` |
| 複数工程の順序制御 | `AcquisitionStartCoordinator` |
| 保存の能力契約 | `VehicleIdentityRepository` |
| その他の能力契約 | `AdapterIdentityProbing`, `ChunkFileStoring` |
| 技術固有実装 | `GRDBVehicleIdentityRepository`, `ELMAdapterIdentityProbe` |
| 利用不能の明示 | `UnavailablePIDVehicleRuntime` |
| テスト用代替 | `FakeVehicleIdentityRepository`, `RecordingEventSink` |

- 「何であるか」を表すprotocolは名詞で命名する。
- 「何ができるか」を表すprotocolは`-able`、`-ible`、`-ing`など能力が読める名前にする。
- 具象実装は、必要な場合に技術名または動作特性を接頭辞へ付け、契約との関係を読めるようにする。

#### 値、状態、集合

- Booleanは`is`、`has`、`can`、`should`などで始め、肯定形で読める名前にする。例: `isConnected`, `hasCapacity`, `canStart`。
- Collectionは複数形、単一値は単数形にする。例: `vehicles`と`selectedVehicle`。
- 件数は`count`、識別子は`ID`、日時は意味に応じて`createdAt`、`startedAt`、`updatedAt`を使い分ける。
- 状態enumは名詞、caseは状態名にする。例: `ConnectionState.connected`。
- Error型は`Error`、具体的な失敗caseは原因または失敗結果が読める名前にする。

### 7.3 APIとメソッドの命名

- メソッド名とargument labelを続けて読むと、自然な英語になるようにする。例: `remove(at:)`, `move(from:to:)`。
- 曖昧さを避けるために必要な語は省略しない。一方、型から明らかな`Object`、`Data`、`Value`などの重複語は付けない。
- 副作用を持つメソッドは動詞で始める。例: `start()`, `persist(_:)`, `remove(at:)`。
- 副作用のない値変換は、結果を表す名詞句または`make`、`formatted`などで表す。
- Factory methodは`make`で始める。例: `makeContainer()`。
- Booleanを返すメソッドは、呼出箇所が条件文として読める名前にする。例: `contains(_:)`, `canStart(in:)`。
- 非同期であることだけを理由に`Async`を付けない。同期版と非同期版を同時に公開し区別が必要な場合だけ使用する。
- argument labelは意味を補う場合に付ける。慣例上自然に読める単一対象は`_`を使用できる。
- 同じ型の値が複数並ぶ場合は、`from`、`to`、`primary`、`secondary`など役割をlabelで区別する。
- default argumentは意味上必須の引数より後ろへ置く。
- closure引数は役割を命名し、複数のBoolean引数で動作を切り替えるAPIを避ける。動作差はenumまたは別メソッドで表す。
- overloadは、呼出箇所とDocCで違いを明確に説明できる場合だけ追加する。

### 7.4 一般的なSwiftコーディング規約

#### 値と型

- 再代入しない値は`var`ではなく`let`で宣言する。
- 型が明確な局所値は型推論を使い、公開契約、空Collection、曖昧な数値では型を明示する。
- 値として表現できるものは`struct`または`enum`を優先する。共有identity、生存期間、参照共有が責任の場合に`class`または`actor`を使う。
- 無効な状態を表現できない型を優先し、相互依存する複数Booleanで状態機械を作らない。
- 意味を持つ複数値はtupleのまま広域へ公開せず、名前付きの型にする。局所的な一時値ではtupleを使用できる。

#### Optionalと制御フロー

- 値の不在が正当な状態である場合だけOptionalを使う。失敗理由が必要ならResultまたはtyped errorを使う。
- 正常経路を浅く保つため、事前条件や失敗条件は`guard`で早期returnする。
- enumは`switch`で網羅的に扱い、新しいcaseを暗黙に無視しない。
- `if let`、`guard let`、nil coalescingを使い、強制unwrapは成立条件が構造的に保証される場合だけに限定する。
- `as!`による強制castを避け、protocol、generic、条件castで表現する。

#### Errorと副作用

- 回復または分類が必要な失敗は`throw`し、業務上の失敗型へ変換する。
- `try?`でerrorを捨てる場合は、不在と失敗を区別しなくてよい理由をDocCまたは周辺コードで明確にする。
- `fatalError`、`preconditionFailure`は、回復不能なプログラマエラーまたは起動不能条件に限定する。
- 副作用を持つ処理は、対象と完了時点が名前とDocCから分かるようにする。
- Global mutable stateを作らない。状態の所有者と生存期間を型で明確にする。

#### 依存とアクセス制御

- 依存はinitializerで受け取り、型の内部でProduction実装を生成しない。
- 具体型ではなく、必要最小限のprotocolまたはclosureへ依存する。
- 公開範囲は必要最小限にする。まず`private`またはmodule内を検討する。
- importは使用するmoduleだけを記載し、層境界を越えるimportを追加しない。
- extensionはprotocol conformance、責任単位、または読みやすい機能単位で分ける。

#### Concurrency

- UI状態は`@MainActor`で所有する。
- 共有可変状態はactor、または一つの明確な所有者へ閉じ込める。
- 非同期処理は所有者を明確にし、取消し後や旧世代の完了結果を状態へ反映しない。
- `Task.detached`はactor contextを意図的に切り離す必要がある場合だけ使用する。
- `Sendable`違反を`@unchecked Sendable`で隠さない。使用する場合は安全性の根拠をDocCへ記載する。
- completion handlerより`async` / `await`を優先し、継続処理が必要な既存API境界だけをbridgeする。

#### 書式とソース構成

- 既存ファイルとSwift標準ライブラリの表記に合わせ、読みやすい単位で改行する。
- コメントは「なぜ」「契約」「制約」を説明し、コードを逐語的に言い換えない。
- Formatterを導入した場合は、その出力を正とし、個人の好みによる整形差分を作らない。

### 7.5 Swift DocC

JavaのJavadocに相当するSwiftの正式な仕組みは、Swift DocCのDocumentation Commentsです。`///` で宣言の直前に記述します。

新規または変更する次の宣言には、アクセスレベルを問わずDocCを必須とします。

- `class`、`struct`、`actor`、`enum`、`protocol`
- `initializer`
- instance method、type method、`private` method
- `subscript`、`typealias`、`associatedtype`

プロパティは、名前だけでは責任、単位、所有権、生存期間、状態の意味が確定しない場合にDocCを必須とします。

型のDocCには、最低限次を記載します。

1. その型が所有する一つの責任
2. どの入力を、どの出力または状態へ変えるか
3. 外部I/O、副作用、actor制約がある場合はその条件

メソッドとinitializerのDocCには、該当する項目を記載します。

- その宣言が完了させる一つの処理
- `- Parameters:` または `- Parameter:`
- 戻り値がある場合は `- Returns:`
- errorを送出する場合は `- Throws:`
- 永続化、通信、ファイル変更、状態更新などの副作用
- `MainActor`、排他、呼出順序、事前条件がある場合はその条件

```swift
/// 収集開始前の検査結果を受け取り、Sessionを作成できるか判定します。
///
/// DBや通信を直接操作せず、渡された検査結果だけを評価します。
struct AcquisitionStartEligibilityEvaluator {
    /// 検査結果を、開始許可または拒否理由へ分類します。
    /// - Parameter inspection: 容量、鍵、Adapter準備状態を含む検査結果。
    /// - Returns: 開始可能な場合は許可、できない場合は安定した拒否理由。
    func evaluate(_ inspection: AcquisitionStartInspection) -> AcquisitionStartEligibility {
        // Implementation
    }
}
```

```swift
/// 確定済みChunkを永続ストアへ一度だけ登録します。
/// - Parameter chunk: ファイル確定後のChunk情報。
/// - Returns: 永続化された目録の識別子。
/// - Throws: transactionを完了できず、目録が確定していない場合のエラー。
/// - Important: ファイルの作成や削除は行いません。
func register(_ chunk: FinalizedChunkFile) throws -> AcquisitionChunkCatalogReference
```

次のコメントは不合格とします。

- 宣言名を日本語へ言い換えただけのコメント
- 実装と一致しない過去の説明
- 「データを処理する」など入力、出力、責任が特定できない説明
- 一つの型やメソッドへ複数責任があることを、長いコメントで正当化する説明

DocCを書いても責任を一文で説明できない場合は、コメントを長くするのではなく設計を分割します。レビューではDocCと実装を一つの契約として確認します。

### 7.6 データと通信

- 一つのデータ種別にSystem of Recordを一つ決める。
- Domain型をSwiftData `@Model`、GRDB Record、通信DTOとして兼用しない。

### 7.7 準拠資料

Swift言語仕様または公式ガイドと本規約が矛盾する場合は、対応するSwift toolchainの公式仕様を優先します。

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/)

## 8. テスト戦略

テストは数ではなく、工程境界と重要な判定を守るために置きます。

単体テストの優先対象:

1. `Domain` の判定、計算、状態分類
2. `Application` の状態遷移、処理順序、取消し、異常分岐
3. `Data` の変換、Migration、永続化原子性、通信フレーミング

通常のCIでは次だけを必須とします。

| CI工程 | 目的 |
|---|---|
| 構造・DocC検査 | 禁止import、逆依存、変更宣言のDocC不足を短時間で検出する |
| macOS Unit Tests | Domain / Application / Dataの単体テストを実行する |
| iOS Simulator Build | iOS固有コードのコンパイル破損を検出する |

通常CIに含めないもの:

- UIの見た目承認
- 実車、実Adapter、USB実機確認
- TestFlight配布確認
- Production外部サービス確認
- 網羅率を上げるためだけの重複テスト

これらが必要な変更は、通常CIとは別の検証工程またはリリースチェックとして扱います。

TestFlightは`main`への通常CIとは別のDelivery工程です。CI成功とTestFlight配布成功を同じ証拠として扱いません。

## 9. 完了条件

通常の変更は次の4点で完了とします。

1. 変更した型の所属工程と責任がこの文書で説明できる。
2. 新規・変更した型とメソッドのDocCが実装上の責任と一致している。
3. 変更に対応する単体テストが必要な場合は追加されている。
4. 必須CIが成功している。

アーキテクチャ境界を変える場合だけ、この文書も同じ変更で更新します。個別実装の説明をアーキテクチャ文書へ追加し続けません。

## 10. 運用

- 本文書をProject 24Zのアーキテクチャとコーディング規約の正本とする。
- 新規コードと変更対象の既存コードに適用する。
- 規約の例外が必要な場合は、理由、影響範囲、終了条件を変更箇所のDocCまたは設計記録へ残す。
- アーキテクチャの責任分界を変える場合は、実装と同じ変更単位で本文書を更新する。
- 詳細設計文書は必要な機能の技術資料として扱い、常時必読ルールにはしない。

CI運用は次の構成へ移行します。

1. `Scripts/validate_structure.sh` を依存方向、配置、変更宣言のDocC検査に限定する。
2. 通常CIを「構造・DocC検査、macOS Unit Tests、iOS Simulator Build」の3工程にする。
3. TestFlight workflowはDelivery専用として分離する。

CI workflowの移行が完了するまでは、本文書の設計・命名・DocC規約を先行適用し、CIに関する完了条件は既存workflowが提供する範囲で判定します。

この文書の役割は、細かな禁止事項を増やすことではありません。誰が見ても、部品の所属工程、前後の入出力、不具合の停止位置を説明できる状態を保つことです。
