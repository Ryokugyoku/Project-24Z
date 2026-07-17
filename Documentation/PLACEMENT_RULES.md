# Placement Rules

新しいファイルは、最初に以下の質問で配置先を決めます。

| 質問 | 配置先 |
|---|---|
| DBやUIを知らない業務上の値・規則か | `Domain/Models` または `Domain/Services` |
| 保存・通信の能力を抽象化するprotocolか | `Domain/Repositories` |
| ユーザー操作、状態遷移、ユースケースか | `Application/<Feature>` |
| SwiftData固有の型・実装か | `Data/Persistence/SwiftData` |
| GRDB固有の型・SQL・Migrationか | `Data/Persistence/GRDB` |
| API／DTO／HTTP実装か | `Data/Networking` |
| iPhone／iPadの画面・遷移・操作か | `Platform/iOS` |
| Macの画面・ウインドウ・コマンドか | `Platform/macOS` |
| 依存生成や起動処理か | `App` |
| レイアウトを持たない色・文字・画像資産か | `Shared` |

## ファイル命名

- Domain: `Vehicle.swift`, `Trip.swift`, `TripRepository.swift`
- Application: `TripListModel.swift`, `StartTripUseCase.swift`
- SwiftData: `SwiftDataTrip.swift`, `SwiftDataTripRepository.swift`
- GRDB: `GRDBTripRecord.swift`, `GRDBTripRepository.swift`, `DatabaseMigratorFactory.swift`
- iOS: `IOSTripListView.swift`, `IOSTripDetailView.swift`
- macOS: `MacOSTripListView.swift`, `MacOSTripDetailView.swift`
- protocolの具象実装は技術名を接頭辞にし、保存方式を隠さない。

`Common`、`Misc`、`Helpers`、`Managers` は新設禁止です。責務を説明できる具体名にします。

## Platform分離

- iOSとmacOSで同じ画面要件でも、Viewファイルを共有しません。
- プラットフォーム条件はAppのルート選択、または各Platformファイル全体を囲む用途に限定します。
- `body`内部で `#if os(iOS)` と `#if os(macOS)` を切り替える実装は禁止します。
- ViewModel／Application Modelは共有できます。ただし画面サイズ、NavigationSplitView、Toolbar placementなどのレイアウト状態を持たせません。
- iPad対応はiOS配下で行い、利用可能領域とsize classに応じてiOS内で再構成します。
- Preview、Snapshot、UI Testもプラットフォーム別に作ります。

## テスト配置

- 純粋ロジック: `Project 24ZTests/Domain/<Feature>`
- Application Model／Use Case: `Project 24ZTests/Application/<Feature>`
- SwiftData Adapter: `Project 24ZTests/Data/Persistence/SwiftData`
- GRDB Adapter／Migration: `Project 24ZTests/Data/Persistence/GRDB`
- iOS UIフロー: `Project 24ZUITests/iOS`
- macOS UIフロー: `Project 24ZUITests/macOS`

テスト用Fakeは、最も狭いテストフォルダ内の `TestDoubles` に置き、本体ターゲットへ含めません。
