# Project 24Z Repository Rules

このファイルは、人間とCodexを含むすべての実装者に適用する最上位ルールです。

## 作業開始時の必須手順

1. `AGENTS.md`、`Documentation/ARCHITECTURE.md`、`Documentation/PLACEMENT_RULES.md` を読む。
2. Git管理下であれば `git status --short` を確認し、既存の変更を上書きしない。
3. 変更対象と直接依存だけを読み、依頼範囲外の挙動を変更しない。
4. 実装前に配置先と依存方向を決める。迷う場合は `Documentation/PLACEMENT_RULES.md` に従う。

## 絶対ルール

- 単一責任の原則を守る。1型・1ファイルを原則とし、画面、状態管理、業務ルール、保存処理を同じ型に混在させない。
- SwiftUI ViewからSwiftData、GRDB、ファイル、ネットワークを直接操作しない。Applicationのモデル／ユースケースとDomainのprotocolを経由する。
- DomainはSwiftUI、SwiftData、GRDB、UIKit、AppKitをimportしない。
- ApplicationはSwiftUI、SwiftData、GRDB、UIKit、AppKitをimportしない。
- DataはDomainのprotocolを実装する。DataからPlatformへ依存しない。
- AppはComposition Rootに限定し、依存生成とプラットフォームルートの選択以外の業務処理を置かない。
- iOSとmacOSのレイアウトは完全分離する。共通View、巨大な `#if os(...)` View、端末判定によるレイアウト切替は禁止する。
- iOS画面は `Platform/iOS/`、macOS画面は `Platform/macOS/` に置く。各プラットフォームの画面階層、ナビゲーション、ツールバー、ウインドウ構成を独立実装する。
- 共有できるのはDomain、Application、表示専用の値、色・文字スタイル・画像などレイアウトを持たない資産だけとする。
- iOS画面ではAppKit、macOS画面ではUIKitをimportしない。
- SwiftDataモデルをDomainモデルとして公開しない。GRDBのRow/Record型もData層の外へ公開しない。
- 同じデータをSwiftDataとGRDBの双方で正本にしない。データ種別ごとに唯一のSystem of Recordを決め、`Documentation/DATABASE_OPERATIONS.md` を更新する。
- 新規／変更するSwift型、protocol、メソッド、initializer、privateメソッドにはSwift DocCコメントを付け、責務、引数、戻り値、throws、副作用、actor条件を必要に応じて記載する。
- 秘密情報、実データ、生成DB、DerivedData、ユーザー固有のXcode状態をコミット対象にしない。

## 依存方向

`Platform -> Application -> Domain <- Data`

`App` は上記を組み立てます。`Shared` はレイアウトや業務ルールを持たず、どの層からも逆依存を作らないものだけを収容します。

## 完了条件

1. `Scripts/validate_structure.sh` が成功する。
2. 変更したDomain／Application／Dataに対応する単体テストを追加または更新する。
3. macOSビルドとiOS Simulatorビルドを個別に実行する。
4. UI変更は両プラットフォームを別々に確認する。ビルド成功をレイアウト確認済みとは扱わない。
5. DB変更はマイグレーション、ロールバック／復旧方針、既存データ互換性を確認する。
6. TestFlight設定を変更した場合は `Documentation/TESTFLIGHT_RELEASE.md` と `.github/workflows/testflight.yml` を同じ変更単位で更新する。

## 禁止される近道

- `ContentView.swift` に全機能を集約する。
- View内に `@Query`、SQL、`ModelContext`操作を置く。
- `Shared/Views` を作り、iOSとmacOSで同じレイアウトを使う。
- ファイル名だけを `Manager`、`Helper`、`Utils` として責務を曖昧にする。
- 将来用途だけを理由に未使用の抽象化やDBテーブルを作る。
- 既存DBを削除してマイグレーション問題を隠す。
