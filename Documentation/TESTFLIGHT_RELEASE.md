# TestFlight Release

`.github/workflows/testflight.yml` は、`main`へのPushごとにiOSアプリとmacOSアプリを個別にビルドし、App Store Connectへアップロードします。手動実行にも対応します。

## 有効化前のApple側準備

1. App Store ConnectにBundle ID `Ryokugyoku.Project-24Z` のiOSアプリレコードを作成し、同じレコードへmacOSプラットフォームを追加する。
2. Account HolderまたはAdminが、クラウド署名とProvisioning操作のできるAdmin権限のTeam API Keyを作成する。
3. 以下のGitHub Actions Repository Secretsを登録する。
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_PRIVATE_KEY`: ダウンロードした`.p8`の全文
4. Repository Variable `TESTFLIGHT_ENABLED` を `true` に設定する。

API秘密鍵はGitHub Secretsだけに保存し、リポジトリやログへ書き込みません。個人API KeyはProvisioning APIを利用できないため、このワークフローにはTeam API Keyを使用します。Adminキーはこのリポジトリ専用とし、他プロジェクトでは再利用しません。

## リリース動作

- GitHubの`macos-26` RunnerとXcode 26.4を使用します。
- 構造検査とApplication単体テストの成功後、iOSとmacOSを別々のArchiveへ出力します。
- 両プラットフォームでGitHub ActionsのRun NumberをBuild Numberとして使用します。
- Xcodeの自動署名とApp Store Connect API Keyを使用して必要なProvisioningを解決します。
- iOSとmacOSで独立したExport Optionsを使い、`destination=upload`により各Export時にApp Store Connectへ送信します。
- macOS Archive後に署名済みAppのApp Sandbox、serial、USB entitlementを読戻し検査し、欠落時はUpload前に失敗します。
- Apple側で処理が完了すると各プラットフォームのTestFlightビルドとして表示されます。初回は輸出コンプライアンスなどの追加回答が必要になる場合があります。

## 安全装置

`TESTFLIGHT_ENABLED=true`になるまでRelease jobは実行されません。資格情報が未登録の状態で初回Pushしても、署名やアップロードは開始しません。

## OBDLink EX実車pilotの確認先

- OBDLink EX USBの車両識別pilotはmacOS TestFlight版で確認します。iOS版はUSB serial Transportを持たず、同じ接続能力を表示しません。
- Release構成はmacOSだけ`com.apple.security.device.serial`と`com.apple.security.device.usb`を要求します。Archiveの署名済みentitlement確認は、実Mac、Driver、Adapter、車両通信の成功証拠ではありません。
- 実機では車両管理画面から一回のread-only識別を実行し、VIN取得、登録確認、Session所属、HOMEの取得成功PID一覧を個別に確認します。
- VIN平文、USB endpoint、Raw応答を通常ログへ出しません。失敗時はTransportを閉じ、登録成功へ昇格しません。
