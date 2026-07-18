# Architecture

Project 24Zは、機能の増加と永続化方式の追加に耐えられるよう、レイヤーとプラットフォームを分離します。

## フォルダ構成

```text
Project 24Z/
├── App/                         # @main、Composition Root、依存注入
├── Domain/
│   ├── Models/                  # 純粋な業務エンティティ
│   ├── Repositories/            # 保存・外部I/Oのprotocol
│   └── Services/                # 複数モデルにまたがる純粋な業務ルール
├── Application/
│   └── <Feature>/               # ユースケース、画面状態、操作の調停
├── Data/
│   ├── Persistence/
│   │   ├── SwiftData/           # ModelContainer、@Model、Repository実装
│   │   └── GRDB/                # DatabaseQueue/Pool、Record、Migration
│   ├── Networking/              # API Client、DTO、Repository実装
│   └── FileSystem/              # ファイル保存のAdapter
├── Platform/
│   ├── iOS/                     # iOS専用SwiftUI View・画面遷移
│   └── macOS/                   # macOS専用SwiftUI View・ウインドウ構成
├── Shared/
│   ├── DesignSystem/            # 色、タイポグラフィ、非レイアウト資産
│   └── Resources/               # Localization、画像、設定資産
└── Assets.xcassets
```

テストは本体の構造を反映します。

```text
Project 24ZTests/
├── Domain/
├── Application/
└── Data/
Project 24ZUITests/
├── iOS/
└── macOS/
```

## 依存関係

```mermaid
flowchart LR
    iOS["Platform/iOS"] --> Application
    macOS["Platform/macOS"] --> Application
    Application --> Domain
    SwiftData["Data/SwiftData"] --> Domain
    GRDB["Data/GRDB"] --> Domain
    App --> iOS
    App --> macOS
    App --> SwiftData
    App --> GRDB
```

- Domainは最も内側にあり、Apple UI／DBフレームワークを知りません。
- Applicationは操作の順序と画面状態を管理しますが、具体的な保存方法を知りません。
- DataはDomain protocolのAdapterです。SwiftDataとGRDBは互いを直接参照しません。
- Platformは表示と入力に専念します。iOSとmacOSは別々のViewツリーを持ちます。
- Appだけが具象型を生成し、protocolへ接続します。

## レイアウトとサービスの分離

PlatformのViewは、Applicationが公開する画面状態を描画し、ユーザー操作をApplicationの操作境界へ通知します。Viewからサービス、ユースケース、Repository、OBD通信Adapter、永続化Adapterを生成または直接呼び出してはいけません。

Applicationは画面に必要な状態遷移と操作を公開しますが、余白、配置、画面幅、NavigationSplitView、Toolbar placementなどのレイアウト情報を持ちません。DomainとDataもレイアウトを知りません。これにより、iOSまたはmacOSのViewツリーを全面的に作り直しても、Domain、Application、Dataの変更を不要にします。

初期実装のUIは、機能要件とアクセシビリティを満たすApple標準部品による最小構成を原則とします。独自の視覚表現は、画面要件として承認された変更単位でPlatformへ追加します。

## 機能追加の単位

機能は、必要な層だけに同じ機能名のまとまりを作ります。たとえばVehicle機能なら、`Domain/Models/Vehicle.swift`、`Application/Vehicles/`、`Platform/iOS/Features/Vehicles/`、`Platform/macOS/Features/Vehicles/` を使用します。空の層や将来用ファイルは作りません。

複数責務が生じた時点で型を分離します。ファイル行数だけでは分割せず、「変更理由が二つ以上あるか」を基準にします。
