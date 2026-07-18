# 接続設定・ログ収集開始 実装製造依頼書

## 1. 文書状態

- Product decision status: 承認済み
- 対象Version: 初期版 Connection Settings Version 1
- 承認日: 2026-07-18
- 製品優先度: 高
- 対象画面: 設定画面 ＞ 接続設定、ダッシュボードのログ収集開始導線
- 製品上の位置付け: PIDデータ取得・保存を開始する中核導線
- レイアウト状態: 初期製造用の簡素なPlatform別レイアウト。将来全面刷新予定
- 正本設計:
  - `OBD_CAN_COMMUNICATION_RUNTIME_DESIGN.md`
  - `ACQUISITION_SESSION_STORAGE_DESIGN.md`
  - `PID_VEHICLE_IDENTIFICATION_REGISTRATION_FLOW_DESIGN.md`
- 実機確認用の開発専用画面: `DEVELOPMENT_DATABASE_BROWSER_IMPLEMENTATION_REQUEST.md`

本書は、接続設定でPrimary／Secondary Adapter候補を既定化し、ダッシュボードから安全にログ収集を開始するための承認済み製品要件と製造境界を定めます。

本書は、特定Adapter、firmware、Transport、ELM command、PID Catalog、Polling周期が技術的に成立したことを証明しません。正本設計のHard Gateが未達の場合、対象能力を利用不可として表示し、推測値、任意command、仮Identity、未検証Transportで迂回しません。

## 2. 製造目的

初期版で次の利用体験を成立させます。

1. 利用者が設定画面の接続設定からPID用Primary Adapter候補を選択する。
2. 利用者が必要に応じてRaw CAN用Secondary Adapter候補を選択する。
3. 選択結果を端末別・役割別の既定候補としてローカル保存する。
4. 設定画面ではAdapterへ接続せず、Sessionやログを作らない。
5. ダッシュボードはPrimary未設定時に接続設定への導線を表示する。
6. ダッシュボードで利用者が明示的にログ収集開始を要求したときだけ、実Adapter接続、Identity／能力確認、Session作成、PID／Raw CAN取得へ進む。
7. 接続失敗時はSessionを作成せず、利用者が理解できる失敗理由と再試行／設定変更導線を表示する。

設定と取得を分離し、「Adapter候補を選択した」「Adapterへ接続できた」「車両と通信できた」「PID／Raw CANを保存した」を同じ成功状態として扱いません。

## 3. 用語と責務境界

| 用語 | 本書での意味 |
|---|---|
| Primary Adapter候補 | OBD、車両識別、PID Pollingへ使用する端末別の既定Endpoint候補 |
| Secondary Adapter候補 | Raw CAN receive-onlyへ使用する端末別の任意Endpoint候補 |
| 既定候補 | 次回開始時に優先して再探索する設定。物理Adapter Identityの検証済み証拠ではない |
| Endpoint候補 | USB path、Bluetooth discovery identifier等、Transport上の到達候補 |
| AdapterReference | 接続後に承認済みIdentity規則で確認する不透明な物理Adapter参照 |
| 接続準備完了 | 対象Transport、Adapter Identity、firmware、能力、allowlistが現在の開始条件を満たす状態 |
| Session | 一回の明示的な取得開始から終端までのPID／Raw CAN保存境界 |
| ダッシュボード | ログ収集開始／停止と取得状態を表示する中核画面。現在のHOME destinationを将来置換できる画面機能境界 |

設定画面で保存する既定候補を、確認済みAdapterReference、車両Identity、車両登録、PID対応、Raw CAN安全性の証拠として使用しません。

## 4. 承認済み製品判断

### CS-P-001 保存範囲

- 既定Adapter候補は端末ごとにローカル保存します。
- PrimaryとSecondaryを別の設定として保存し、各役割のActive既定候補は最大1件とします。
- iPhoneの既定候補をMacへ同期せず、Macの既定候補をiPhoneへ同期しません。
- ユーザー全体の共通設定、車両別設定、Session別設定へ暗黙に昇格させません。
- 設定を変更しても過去SessionのAdapterReference、Stream、Chunkを更新しません。

### CS-P-002 既定候補の意味

- 設定画面で選択したEndpoint候補を既定候補として保存します。
- 選択時点では、同名、OS identifier、USB path、Bluetooth表示名だけで物理Adapter Identityを確定しません。
- 実際のAdapter Identityはログ収集開始時の接続後に確認します。
- 保存済みの確認済みIdentity根拠と現在のIdentityが一致する場合だけ、同じAdapterとして使用します。
- Identityが不一致または不明の場合はログ収集を開始せず、利用者へ再選択を要求します。
- 初回のIdentity確認成功時に確認済みbindingを保存する場合、既定候補を別物理Adapterへ黙って置換しません。
- Adapter交換は接続設定から利用者が明示的に行います。

### CS-P-003 設定画面では接続しない

- 接続設定ではEndpoint探索と選択だけを行います。
- 設定画面でUSB／Bluetooth AdapterへTransport接続しません。
- Adapter初期化、firmware取得、Capability probe、PID Request、車両識別、Raw CAN monitor開始を行いません。
- Acquisition Session、Stream、Clock Epoch、Gap、Chunk、Vehicle Scanを作成しません。
- PID／Raw CAN Payload、車両応答、接続Transcriptを取得・保存しません。
- 設定画面を閉じた後に接続、探索task、取得taskを残しません。Bluetooth探索は選択画面のLifecycleに合わせて停止します。

### CS-P-004 Bluetooth権限

- アプリ起動時にはBluetooth権限を要求しません。
- 利用者が「Bluetoothデバイスを選択」を開始した時に、対象Platformの標準手順で権限を要求します。
- 権限拒否、制限、未対応をそれぞれ区別して表示します。
- 権限拒否時にUSB、Wi-Fi、別Transportへ自動Fallbackしません。
- OS設定をアプリが自動変更せず、必要な場合だけ設定確認方法を案内します。

### CS-P-005 対応方式の表示

- 対象Platform、配布構成、Adapter製品、firmwareで利用可能と確認されたTransportだけを選択可能として表示します。
- macOSでは、Hard Gateを通過したUSBまたはBluetooth方式だけを有効化します。
- iPhoneでは、Hard Gateを通過したBluetooth方式だけを初期候補とし、USBを初期版の選択肢にしません。
- Bluetooth LEとBluetooth Classic／MFiをData／能力判定上の別Transportとして扱います。利用者向け表示を「Bluetooth」とまとめる場合も、内部で同一実装へ統合しません。
- 未検証、非対応、権限不足、現在利用不能を「利用可能」と表示しません。
- 対応Adapter製品・firmwareの正式一覧が未確定の間はProduction接続を有効化しません。

### CS-P-006 Primary／Secondary

- PrimaryはOBD、車両識別、PID Polling専用です。
- SecondaryはRaw CAN receive-only専用です。
- Primaryはログ収集開始に必須、Secondaryは任意です。
- 両方を使用する場合は別の物理Adapterを必須とします。
- 同一性が不明な2候補を別Adapterと推測しません。
- 同一Session内で役割変更、Adapter交換、同一Adapter兼用を行いません。
- PrimaryとSecondaryは、それぞれ独立したConnection Runtime、Generation、状態、retry、診断識別子を持ちます。
- 両方を使用するSessionでは、Session commit後にPID取得とRaw CAN受信を論理的に並行して実行します。完全に同一時刻の開始を保証する表現は使用しません。

### CS-P-007 Secondary開始失敗

- Secondary未設定時はPrimaryだけのPID Sessionとして開始できます。
- Secondary設定済みでPrimary／Secondary両方が準備完了した場合はPID＋Raw CAN Sessionとして開始します。
- Secondary設定済みでSecondaryだけが開始前に失敗した場合は、Session作成前に次を提示します。
  - 「PIDのみで開始」
  - 「キャンセル」
- 利用者の確認なしにPIDだけへ自動縮退しません。
- 「PIDのみで開始」が選択された場合、Secondary Streamを作らず、開始前失敗をRaw CAN Gapとして捏造しません。
- Primary開始前失敗ではPID／Raw CAN Sessionを作らず、Secondaryだけの自動開始もしません。

### CS-P-008 PID個別設定の保留

- PID番号、表示項目、取得対象集合、優先度、Formula、unit、周期、timeout、retry、batch設定を接続設定へ置くかは製品判断保留です。
- 本製造単位ではPID個別設定UI、手動PID入力、Formula入力、Polling周期入力を実装しません。
- 製造担当は「一般的だから」「将来必要だから」を理由に既定PID集合や設定画面を追加しません。
- PID Catalog、対応探索、Polling plan、Raw保存の既存安全契約を変更しません。
- Product decisionと実Adapter／実車検証が完了した別変更単位でのみ追加します。

## 5. 設定画面 ＞ 接続設定

### 5.1 画面の役割

接続設定は、端末ローカルのPrimary／Secondary既定候補を選択、変更、解除する別画面です。ダッシュボード、車両管理、PID表示へ設定操作を埋め込みません。

### 5.2 Primary Adapter

最低限、次を表示・操作できるようにします。

- 役割: 「OBD・PID用」
- 設定必須であること
- 現在の接続方式
- 現在の既定候補の非機密表示名
- 未設定状態
- USBデバイスを選択
- Bluetoothデバイスを選択
- 既定候補を変更
- 既定候補を解除
- Transportが未対応または権限拒否で選択できない理由

選択画面は、Endpointの表示名、Transport種別、選択に必要な非機密情報だけを表示します。秘密ID、MAC address、USB serial、内部UUID、Raw advertisement bytesを通常画面へ表示しません。

### 5.3 Secondary Adapter

最低限、次を表示・操作できるようにします。

- 役割: 「Raw CAN受信専用」
- 任意設定であること
- 現在の接続方式
- 現在の既定候補の非機密表示名
- 未設定状態
- USBデバイスを選択
- Bluetoothデバイスを選択
- 既定候補を変更
- 既定候補を解除
- Primaryと同じEndpoint候補を選択できない理由
- 別物理Adapterであることはログ収集開始時まで未確認である旨
- receive-onlyが実機確認済みでない場合の利用不可理由

設定画面では、Primaryと同一のEndpoint候補をSecondaryへ重複設定できません。異なるEndpoint候補同士が別の物理Adapterかどうかは未接続では確定できないため、Secondary候補として暫定保存できますが、「物理Adapter未確認」として扱います。ログ収集開始時に両方へ接続し、別の物理Adapterと確認できなければSessionを作成しません。

Secondary設定中にPrimaryを停止、変更、再割当しません。役割変更は対象設定を解除して別役割へ明示的に選び直します。

### 5.4 保存動作

- 候補選択画面で利用者が「このデバイスを使用」を実行した時点で、既定候補をローカル保存します。別の画面全体保存ボタンは設けません。
- 保存失敗時は選択済みと表示せず、直前の確定済み設定を維持します。
- 同じ候補の再選択は冪等にします。
- Primary／Secondary変更中に片方の確定済み設定を破壊しません。
- 設定解除は過去Session、ログ、車両、確認済みIdentity監査履歴を削除しません。

## 6. ダッシュボードの主操作

### 6.1 ボタン状態

| 条件 | 主ボタン文言 | 有効性 | 操作 |
|---|---|---|---|
| Primary未設定 | 接続設定をする | 有効 | 設定画面 ＞ 接続設定へ遷移 |
| Primary設定済み、非収集中 | ログ収集を開始 | 有効 | 7章の開始フロー |
| 開始処理中 | 接続中、準備中等の現在段階 | 二重操作不可 | 取消し可能境界だけ別Actionで提供 |
| 収集中 | ログ収集を停止 | 有効 | 正本設計の安全な停止順序 |
| DB／容量／鍵利用不可 | ログ収集を開始できません | 無効 | 安定理由と解決導線を表示 |

「接続設定をする」と「ログ収集を開始」を同時に表示しません。表示文言、アクセシビリティLabel、Hint、実行Actionを同じ状態から導出します。

### 6.2 接続失敗表示

開始前に次を区別して表示します。

- 既定候補が現在見つからない
- Bluetooth権限拒否／制限
- USB endpointを開けない
- Transport未対応
- Adapter Identity不一致
- Adapter Identity不明
- PrimaryとSecondaryが同一または区別不能
- Adapter／firmware／mode未対応
- command allowlist未確定
- Raw CAN receive-only安全条件未達
- timeout
- 利用者取消し
- DB、容量、鍵の利用不可

任意の低水準例外文、Endpoint秘密ID、Raw response、VIN、CAN Payloadを通常画面または通常ログへ出しません。利用者向けの安定説明と非機密診断IDを表示できます。

### 6.3 再試行

- Primary開始前失敗では「再試行」「接続設定を開く」「キャンセル」を状態に応じて提供します。
- Identity不一致、権限拒否、非対応、allowlist未達を無条件自動再試行しません。
- 利用者取消し後に探索結果が到着しても自動開始しません。
- 再試行は新Connection Generationを使用し、旧callbackを受理しません。

## 7. ログ収集開始フロー

### 7.1 採用順序

1. 利用者がダッシュボードで「ログ収集を開始」を明示操作する。
2. Primary既定候補が存在することをApplicationが確認する。
3. DB、保存容量、必要Keyの開始前検査を行う。ここではSessionを作成しない。
4. Primary候補を再探索し、Transport接続、Adapter初期化、Identity、firmware、必要能力、allowlistを確認する。
5. Secondary設定済みの場合は別Runtimeで同じ準備を行い、Primaryと別物理Adapterであることとreceive-only Hard Gateを確認する。
6. Primary失敗なら全開始を中止し、全Transportを閉じ、Sessionを作成しない。
7. Secondaryだけが失敗した場合は、CS-P-007の選択を利用者へ提示する。
8. 使用するStream集合が確定した後、`BEGIN IMMEDIATE`でAcquisition Session、PID Stream、必要ならRaw CAN Stream、Clock Epochを作成する。
9. transaction commit成功後だけConnection Runtimeを`acquiring`へ進める。
10. Primaryは車両識別の最小承認済みRequestとPID取得を開始し、Secondaryは承認済みreceive-only monitorを開始する。
11. 車両識別中のRaw request／responseを未割当SessionのPID Streamへ保存する。
12. 登録済みactive車両と確認できた場合だけSessionをその車両へ関連付ける。
13. 未登録、識別不能、Conflict、登録取消しの場合も、既に取得したデータを削除せず未割当Sessionとして継続または安全に終端する。

### 7.2 開始前失敗

開始前失敗では次を保証します。

- Acquisition Session、Stream、Clock Epoch、Gap、Chunkを作成しない。
- PID Request、車両識別Request、Raw CAN monitorを開始しない。
- 一部成功したTransportを閉じる。
- 設定済み既定候補を自動削除・自動置換しない。
- 過去Session、車両、ログを変更しない。

### 7.3 開始後障害

Session commit後の切断、timeout、overflow、Storage障害は開始前失敗へ戻しません。正本設計に従ってGap、Stream状態、Session終端、`recovery_required`を記録し、確定済みデータを削除しません。

Secondary障害は、保存pipelineがPrimaryだけを安全に継続できる場合、Primary PIDを巻き戻しません。安全に継続できない場合はSession全体を安全停止します。どちらを適用したかを利用者へ表示します。

## 8. ELM Adapter境界

- Primary／Secondaryとも、承認済み仕様と実測証拠を持つELM系Adapterを想定します。
- 「ELM互換」という表示だけで製品対応としません。
- 対応単位はAdapter製品、firmware、Transport、mode、allowlist Versionの組です。
- Primaryは承認済み標準OBD read Requestだけを車両busへ送信できます。
- Secondaryの公開境界にCAN frame送信、inject、replay、DTC消去、ECU reset、write／coding、任意command文字列を置きません。
- SecondaryはApp API、Adapter mode仕様、allowlist transcript、車両bus上の実測を別々に確認できるまで開始不能とします。
- Settings View、Dashboard View、ApplicationからELM command bytesや任意文字列を指定できません。

## 9. レイアウト全面刷新に耐える実装境界

### 9.1 必須原則

- iOSとmacOSは別Viewツリー、別Navigation、別画面ファイルとして製造します。
- 初期レイアウトはApple標準UI部品による簡素な構成で構いません。
- Viewの全面削除・再実装がDomain、Application、Data、Migration、保存済み設定の変更を要求しない境界を維持します。
- ViewはApplicationが公開する画面状態を描画し、型付きActionを通知するだけにします。
- ViewからUSB、Bluetooth、Core Bluetooth、Network.framework、GRDB、Keychain、file、ELM Adapterを直接操作しません。
- ViewファイルへService、Use Case、Repository、Transport Adapter、Fakeを定義しません。
- Domain／Application状態へ画面幅、余白、カラム数、sheet高さ、NavigationSplitView選択、toolbar placementを持ち込みません。
- 仮レイアウト専用の状態を永続化しません。
- 設定画面とダッシュボードで同じレイアウトViewを共有しません。

### 9.2 共有可能な境界

共有できるのは次だけです。

- 接続設定Application State
- ダッシュボード取得Application State
- 型付きAction
- 非機密の表示専用値
- Error codeから表示分類へのApplication写像
- 色、文字Style、画像等の非レイアウト資産

### 9.3 Layoutと機能の受入条件

- iOS接続設定Viewを削除して別構造へ置換しても、既定候補の読書き、権限Action、開始判定を変更しない。
- macOS接続設定Viewを削除して別構造へ置換しても、USB／Bluetooth Adapter実装を変更しない。
- ダッシュボードのカード、リスト、ボタン配置を変更しても、主ボタン状態機械と開始Use Caseを変更しない。
- Preview／Fake用の表示StateがProduction RepositoryやTransportへ混入しない。

## 10. 配置と依存方向

実装時は次の責務に分離します。名称は既存型との重複を確認し、責務を表す具体名にします。

| 層 | 責務 |
|---|---|
| Domain/Models | 端末別Role、既定候補、確認済みIdentity binding、開始適格性の純粋な値と規則 |
| Domain/Repositories | 端末ローカル既定候補の保存、Endpoint探索、Transport能力、Identity確認のprotocol |
| Application/ConnectionSettings | 候補探索、選択、保存、解除、権限状態、画面State／Action |
| Application/Acquisition | ダッシュボード主操作、開始前検査、Primary／Secondary準備、縮退確認、Session開始順序 |
| Data/Communication | USB／Bluetooth別探索・接続、Identity／Capability、ELM allowlistの具象Adapter |
| Data/Persistence/GRDB | 既定候補と確認済みbindingの端末ローカルSystem of Record、Migration、Repository |
| Platform/iOS | iOS専用設定画面、候補選択、権限表示、ダッシュボード導線 |
| Platform/macOS | macOS専用設定画面、候補選択、USB／Bluetooth表示、ダッシュボード導線 |
| App | 具象依存生成とPlatform root選択だけ |

依存方向は`Platform -> Application -> Domain <- Data`を維持します。全ての新規・変更Swift宣言、initializer、メソッド、privateメソッドへSwift DocCを付けます。

## 11. 永続化要件

### 11.1 System of Record

- 既定候補、役割、端末スコープ、確認済みIdentity binding、Revision、作成／更新監査のSystem of RecordはGRDBとします。
- SwiftDataへ同じ設定を複製しません。
- 物理DBは既存の認証済みUser Scope境界に従い、端末Identityまたは承認済みlocal device scopeを複合境界へ含めます。
- 秘密ID、Bluetooth MAC、USB serial、Raw advertisementを平文の通常表示列として保存しません。
- OS提供identifierを保存する場合、寿命、再インストール、再ペアリング、Platform差を技術設計で明示します。

### 11.2 制約

- 端末スコープ／役割ごとにActive既定候補を最大1件とします。
- PrimaryとSecondaryの確認済みAdapterReferenceが同一になる状態を拒否します。
- Identity不明候補を「別Adapter確認済み」へ昇格しません。
- 設定変更履歴または旧bindingを、将来の監査・交換判定に必要な期間保持し、通常更新で過去Sessionへ付け替えません。
- 設定解除を過去ログ、Session、車両、Chunkの削除へcascadeさせません。
- Migration失敗時はrollbackし、既存DBを削除または空DBへFallbackしません。

具体的Schema、暗号化列、Digest、local device scope binding、Migration Versionは技術設計で確定します。製造担当が既存テーブルの意味を拡張して仮保存しません。

## 12. 必須画面状態

### 12.1 接続設定

- Primary未設定
- Primary候補選択中
- Primary保存中
- Primary設定済み
- Primary保存失敗
- Secondary未設定
- Secondary候補選択中
- Secondary保存中
- Secondary設定済み
- Secondary保存失敗
- Bluetooth権限未決定
- Bluetooth権限拒否
- Bluetooth制限中
- 対象Transport非対応
- 候補なし
- Primaryとの同一性が確定／不明でSecondary選択不可

### 12.2 ダッシュボード

- Primary未設定
- 開始可能
- 保存開始条件blocked
- Primary探索中／接続中／初期化中／能力確認中
- Secondary探索中／接続中／安全性確認中
- Secondary失敗によるPIDのみ開始確認
- Session作成中
- 車両確認中
- PIDのみ収集中
- PID＋Raw CAN収集中
- 再接続中
- 利用者判断待ち
- 停止中
- 正常終了
- recovery required
- 開始前失敗
- 開始後障害

低水準状態をそのまま列挙するのではなく、利用者が次に取れるActionとデータ保持状況を分かるように表示します。

## 13. 必須テストと受入条件

### 13.1 Domain／Application

- Primary未設定ではダッシュボード主操作が「接続設定をする」になる。
- Primary設定済みでは主操作が「ログ収集を開始」になる。
- 文言、Label、Hint、Actionが同一状態から導出される。
- Primary／Secondary既定候補が端末別・役割別に分離される。
- iPhone設定がMac設定へ同期されない。
- 同一Endpoint候補をPrimary／Secondaryへ重複保存できない。
- 異なるEndpoint候補を暫定保存できても、別物理Adapterと確認できるまで両StreamのSessionを開始できない。
- 設定画面の全ActionでSession、Stream、Gap、Chunk、Vehicle Scanが作成されない。
- 設定画面の全ActionでTransport接続、ELM command、PID Request、Raw monitorが開始されない。
- Primary開始前失敗でSessionが作成されない。
- Secondary開始前失敗で利用者確認なしにPIDのみへ縮退しない。
- 「PIDのみで開始」時にPID Streamだけが作成される。
- 「キャンセル」時に全Transportを閉じ、Sessionを作成しない。
- Session commit前にPID／Raw CAN取得を開始しない。
- Session commit後の障害を開始前失敗として削除・巻戻ししない。
- stale callback、二重tap、取消し後EventでSessionが重複作成されない。

### 13.2 Data／Persistence

- 役割ごとのActive既定候補最大1件をDB制約とRepositoryで拒否する。
- 別User Scope、別local device scopeの設定を読書きできない。
- 設定変更／解除で過去Session、Stream、Chunk、Vehicleを更新・削除しない。
- Identity不明を確認済みbindingとして保存できない。
- Migration rollback、既存データ互換性、DB再起動読戻しを確認する。
- 秘密情報とRaw Payloadが通常ログへ出ない。

### 13.3 Platform

- iOSとmacOSを別Viewツリーとして確認する。
- iOSで未検証USBを選択可能として表示しない。
- Bluetooth選択開始前に権限を要求しない。
- Bluetooth権限拒否後に別Transportへ自動Fallbackしない。
- 接続設定からダッシュボードへ戻っても選択済み既定候補が表示される。
- Primary未設定時の主ボタンから接続設定へ遷移できる。
- Primary／Secondaryの表示名を認証根拠として表現しない。
- Dynamic Type、VoiceOver、Keyboard、Focus、取消し、二重操作を各Platformで確認する。
- 初期レイアウトを別レイアウトへ置換してもApplicationテストが変更不要である。

## 14. 技術Hard Gate

次は製造担当が推測せず、承認済み技術設計または実機証拠が揃うまで対象能力を利用不可にします。

1. 正式対応するPrimary／Secondary Adapter製品とfirmware。
2. macOS USBの列挙、open、双方向通信、detach、再接続、sandbox、driver、配布entitlement。
3. macOS BluetoothのBLE／Classic選択、profile、service、characteristic、pairing、entitlement。
4. iPhone BluetoothのBLE／Classic-MFi選択、対象Adapter、権限、background条件。
5. Adapter model／firmware／mode別のELM command、framing、timeout、cancel、allowlist。
6. AdapterReferenceとEndpoint候補binding、再ペアリング、OS再インストール、Adapter交換規則。
7. Raw CAN receive-onlyのApp API、allowlist、Adapter仕様、実transcript、車両bus実測。
8. Transport別queue、backpressure、drop検出、再接続上限。
9. 車両再識別条件と識別不能時の継続判断。
10. PID Catalog、Decoder、取得対象、優先度、周期、batch、throughput、実車応答。
11. 既定候補／確認済みbindingのGRDB Schema、暗号化、Digest、Migration。

Hard Gate未達時も設定候補の表示やFake画面を製造できますが、Production接続、PID取得、Raw CAN開始、実車対応済み表示を有効化しません。

## 15. 初期版対象外

- 設定画面での接続確認
- 設定画面でのVehicle Scan、PID support探索、PID Polling、Raw CAN monitor
- 設定画面でのSession／Stream／Chunk作成
- PID個別選択、手動PID、Formula、unit、周期、timeout入力
- 任意ELM／AT／ST command入力
- 未検証Adapterを「互換」として使用するFallback
- iPhone USB
- 同一物理AdapterのPrimary／Secondary兼用
- Session途中のAdapter交換／役割変更
- SecondaryからのCAN送信、inject、replay、診断write
- 既定Adapter設定の端末間同期
- 接続失敗時の空Session作成
- Secondary失敗時の無確認自動縮退
- レイアウト都合の状態や業務判断のView内実装

## 16. 現行実装との差分

現行実装は次の状態です。

- 設定画面／接続設定destinationが存在しない。
- HOMEはプレースホルダーで、ダッシュボード主操作が存在しない。
- Adapter選択UIは車両管理画面内にあり、Production接続はblockedである。
- ProductionはUnavailable Transport／PID Runtime／Event Sinkへ接続されている。
- 端末別・役割別の既定Adapter候補の永続化がない。
- 実USB／Bluetooth Adapter、PID取得、Raw CAN受信は有効化されていない。

製造時は既存車両登録の業務状態、GRDB保存契約、通信Runtime、取得保存基盤をViewへ移植しません。車両管理画面にある仮接続レイアウトを正本UIとして再利用せず、必要なApplication Action／表示値だけを接続設定とダッシュボードへ分離します。

## 17. 製造段階

### Stage A: 要件に沿ったApplication／Persistence設計

- 端末別・役割別の既定候補モデル
- 候補と確認済みIdentity bindingの分離
- GRDB Schema／Migration／rollback／暗号化境界
- 接続設定State／Action
- ダッシュボード主操作State／Action
- Primary／Secondary開始前調停と縮退確認
- Session作成前後の失敗分類

### Stage B: FakeでのPlatform別簡素画面

- iOS設定画面 ＞ 接続設定
- macOS設定画面 ＞ 接続設定
- iOSダッシュボード主操作
- macOSダッシュボード主操作
- 12章の全必須状態のうち、初期画面に必要な代表状態
- レイアウト全面置換可能性の受入確認

Stage BのFake成功を実Adapter、PID取得、Raw CAN受信、実車対応の証拠にしません。

### Stage C: 検証済みTransport／Adapter接続

14章の該当Hard GateをAdapter／firmware／Platform単位で通過した後だけ、Production Transport、Identity、allowlist、開始Use Caseへ接続します。

### Stage D: PID／Raw CAN取得・保存接続

Storage開始transaction、暗号化Chunk、GRDB目録、車両識別、PID Polling、Raw CAN receive-onlyを正本設計の順序で接続します。実Adapter／実車／実端末証拠がない対象を製品対応済みと報告しません。

## 18. 検証と証拠の区分

| 証拠 | 証明できる範囲 |
|---|---|
| 文書／静的検査 | 要件、配置、依存方向、禁止API、DocC |
| Domain／Application単体テスト | 既定候補、主ボタン、開始順序、縮退、取消し、非破壊規則 |
| Data／Migrationテスト | scope、Unique、rollback、読戻し、過去データ非変更 |
| Fake／Preview | 画面StateとAction表現。実接続を証明しない |
| Simulator／build | 対象構成のcompile／画面フロー。実Adapterを証明しない |
| 対象Mac／iPhone＋実Adapter | Transport、権限、Identity、firmware、allowlist、切断復帰 |
| 対象車両＋実Adapter | PID応答、Raw CAN、安全性、throughput、車両識別 |
| ユーザー目視確認 | iOS／macOS各画面の最終レイアウト承認 |

製造完了時は`Scripts/validate_structure.sh`、関連単体／結合テスト、macOS build、iOS Simulator buildを実行します。Swift、永続化、通信、設計契約を変更した場合はDocC、設計文書、Persistence契約の検査も実行します。実機または目視確認をしていない場合は未検証として明記します。

## 19. 製造担当の完了報告

1. 実装したStageと変更ファイル。
2. 承認済み要件へ対応するState、Action、Repository、Migration、Platform画面。
3. 実行した検証と結果。
4. Fake、Simulator、build、実Adapter、実車、目視確認を分離した証拠。
5. 未達Hard Gateと利用不可にした能力。
6. PID個別設定へ独自判断を加えていないこと。
7. 過去Session、車両、ログ、Chunk、既定設定を破壊していないこと。

未達Hard Gateを仮接続、任意command、空Session、未確認自動縮退、未検証Adapter対応表示で迂回しません。

## 20. 実機データ確認画面

本要件の実装後に実機DBを確認するため、`DEVELOPMENT_DATABASE_BROWSER_IMPLEMENTATION_REQUEST.md`の開発専用別画面を同じ製造計画へ含めます。

- iOSとmacOSの両方へ別Viewとして用意します。
- GRDBの全Application table、全列、全行へ到達可能にします。
- SwiftDataは内部SQLiteを直接openせず、明示対応したApplication modelを論理データセットとして表示します。
- Pull-down／Pickerでデータソースとtableを切り替えます。
- table領域内で縦横scrollできるようにします。
- Development buildおよび承認済みTestFlight buildで利用可能、完全read-onlyとし、App Store提出用Production buildでは除外します。
- 接続設定、ログ収集、車両登録のProduction境界へ閲覧用SQLやDevelopment依存を混入させません。
