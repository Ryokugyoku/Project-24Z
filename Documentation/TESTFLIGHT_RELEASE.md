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
- Apple側で処理が完了すると各プラットフォームのTestFlightビルドとして表示されます。初回は輸出コンプライアンスなどの追加回答が必要になる場合があります。

## 安全装置

`TESTFLIGHT_ENABLED=true`になるまでRelease jobは実行されません。資格情報が未登録の状態で初回Pushしても、署名やアップロードは開始しません。
