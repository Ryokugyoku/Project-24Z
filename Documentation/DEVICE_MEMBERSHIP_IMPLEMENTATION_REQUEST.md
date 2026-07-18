# Device Membership 実装製造依頼書

## 1. 文書状態

- Product decision status: 承認済み
- 対象Version: 初期版Device Membership Version 1
- 承認日: 2026-07-18
- 製品優先度: 中
- 製品上の位置付け: HOMEおよびPIDデータ取得・保存を支える補助機能
- 実装開始状態: 技術成立性確認待ち
- 正本設計: `DEVICE_PAIRING_SYNC_CONFLICT_DESIGN.md`

本書は、Project 24ZでiPhoneとMacを同じユーザーの端末として所属させるDevice Membershipについて、承認済みの製品要件と製造担当への依頼範囲を定めます。暗号方式、TLS Identity、canonical codec等の技術値を推測で決める文書ではありません。

`DEVICE_PAIRING_SYNC_CONFLICT_DESIGN.md`の安全条件、非破壊条件、データ境界は本書より優先します。本書で確定した製品判断を技術仕様へ反映するとき、既存設計のHard Gateを弱めてはなりません。

## 2. 製造目的

初期版で、次の利用体験を安全に成立させます。

1. iPhoneが新しいユーザー領域を作成する。
2. 既存の信頼済み端末が、新しいiPhoneまたはMacを対面で承認する。
3. Membership確立後だけPairing、Trust、Primary Mac割当へ進める。
4. 紛失・売却した端末を、残っている信頼済み端末から失効できる。
5. Primary Macを旧Mac不在でも交換できる。
6. 全信頼済み端末を失った場合は、既存Membershipを推測復旧しない。

Membershipはユーザー、端末、車両、取得Sessionを同一Entityにまとめる機能ではありません。Membershipが証明するのは、Device Identityが同じUser Scopeへの参加を承認されたことだけです。

本機能の製品優先度は中とします。HOME画面とPIDからのデータ取得・保存を高優先の中核機能とし、Membershipのためにそれらのローカル製造、検証、利用開始を待たせません。MembershipのHard Gateが停止するのは、端末間のMembership確立、Pairing、Trust、Primary Mac割当および同期であり、単一端末内のHOME表示、PID取得、ローカル保存ではありません。

## 3. 用語と責務境界

| 用語 | 本書での意味 |
|---|---|
| User Scope | 同じMembershipに属するデータと鍵の所有境界。内部UUIDを利用者の識別情報として表示しない |
| Device Identity | 端末インストールごとの長期Identity。端末名、Apple Account名、Bluetooth名とは別物 |
| Membership | Device IdentityがUser Scopeへの参加を承認され、必要な鍵Bootstrapを完了した状態 |
| Pairing | 相手Device IdentityをPeerとして登録した関係 |
| Trust | 現在そのPeerとの通信を許可する判断 |
| Primary Mac | 対象iPhoneが終了済みログを送る現在の送信先Mac |
| SAS | 両端末が同じPairing transcriptを見ていることを利用者が確認する短い認証文字列 |

Membership、Pairing、Trust、Primary Mac割当は別の状態軸として実装します。SAS一致、端末名一致、同一LAN、平文`user_scope_id`一致のいずれも、単独ではMembership成立の根拠にしません。

## 4. 承認済み製品要件

### MEM-P-001 最初の端末

- 新しいUser Scopeを作成できる最初の端末はiPhoneだけとします。
- 初回iPhoneは、ランダムなUser Scopeとユーザールート鍵、独立したPairing Membership Key、用途別鍵を生成します。
- User Scope UUID、鍵、Fingerprintを利用者へ入力させません。
- Mac単独では新しいUser Scopeを作成せず、既存User Scopeを端末名やアカウント名から推測しません。
- 初回作成が部分的に失敗した場合、Membershipを`established`にせず、安全な再試行または利用不可状態にします。

### MEM-P-002 新端末の追加

- 2台目以降は、既存の信頼済み端末による明示承認を必須とします。
- 初期版ではAccount Membership Credential、復旧コード、メール、Apple Accountだけによる追加を提供しません。
- 追加時は両端末のアプリが操作可能で、対面確認できることを前提とします。
- 両端末に同じSASを表示し、両方の明示確認を要求します。
- 承認側の最終操作には、利用可能なOS標準のLocal Authenticationを要求します。認証キャンセル、失敗、Lockout時は承認しません。
- 新端末側だけ、またはSASの片側確認だけではMembershipを成立させません。
- Membership Keyと必要な用途別限定鍵の受領、Keychain保存、読戻し、署名・recipient・Version検証が完了した後だけ`membership_state = established`にします。

### MEM-P-003 鍵共有範囲

- ユーザールート鍵そのものを2台目以降へ配送しません。
- 追加端末へ配送できるのは、独立したPairing Membership Keyと、その端末の役割に必要なVersion付き用途別限定鍵だけです。
- Root、Membership、車両識別暗号、Digest、Session／Chunkの鍵Purposeを分離します。
- 受信端末、Trust generation、Key Version、Purposeへ束縛して配送し、別端末・別Purpose・旧Identityへ転用しません。
- 具体的な鍵形式、保持期間、Rotation値は承認済み技術仕様で確定します。

### MEM-P-004 信頼済み端末が残る場合の復旧

- 信頼済み端末が1台以上残っていれば、その端末から新しいiPhoneまたはMacを承認できます。
- iPhone紛失後は、残った信頼済みMacから新iPhoneを新しいDevice Identityとして追加できます。
- Mac交換時は、対象iPhoneから新Macを新しいDevice Identityとして追加できます。
- OS再インストール、Identity鍵喪失、端末バックアップ復元後のアプリは、旧Device Identityを引き継がず新端末追加として扱います。
- 旧Identity、旧Wrapped Key、旧Pairing行を新Identityへ付け替えません。

### MEM-P-005 全信頼済み端末紛失時

- 初期版では、信頼済み端末が0台になった既存User Scopeへの復旧を提供しません。
- 復旧コード、サポート操作、メール、Apple Account、端末名、DB内UUIDだけでMembershipを再確立しません。
- 新しいiPhoneでは、新しいUser Scopeを作成します。
- 旧DB、Archive、Chunk、隔離データを自動削除、自動統合、自動移行しません。
- ArchiveからデータまたはMembershipを復旧する機能は別要件とし、本実装で暗黙に提供しません。
- 初期設定完了前に「すべての信頼済み端末を失うと、既存のユーザー領域へ新端末を追加できない」ことを明示します。

### MEM-P-006 端末失効

- 残っている信頼済み端末の端末一覧から、対象Peerを明示選択して失効できます。
- 失効確定にはOS標準のLocal Authenticationと、対象端末名・役割を示す確認を要求します。
- 失効後は、そのPeerからの新規接続、Change適用、転送、ACK、鍵配送を拒否します。
- 失効したIdentityは、同じ公開鍵で再接続しても自動復帰させません。利用を戻す場合は新規Pairingと同じ確認を要求します。
- 失効は遠隔消去ではありません。紛失端末へ既に保存されたデータ、DB、Chunk、鍵の消去を保証する表現を禁止します。
- 外部サーバーを使わない初期版では、オフライン端末への失効通知や全Peerへの即時反映を保証しません。未到達端末がある場合は、その状態を利用者へ隠しません。
- 自分自身または最後の信頼済み端末を通常のPeer失効操作で失効させません。Membership全体の終了は、非破壊条件とArchive要件を別途確定した専用機能とします。

### MEM-P-007 Primary Mac交換

- 旧Primary Macのオンライン状態または承認を、交換の必須条件にしません。
- 対象iPhoneと新MacのMembership、Pairing、Trust、SAS確認が完了してから新Primary Macを有効化します。
- 最終割当変更は、ログ送信元となる対象iPhone上で利用者が明示確認します。
- 切替前に旧割当、未転送・未ACK Session、鍵Envelopeへの影響を表示します。
- 1台のiPhoneに同時に複数のActive Primary Macを許しません。
- 切替後は旧Macへの新規ログ転送を禁止します。
- 旧MacのTrust、保存済みデータ、鍵を自動失効・自動削除しません。必要な場合は利用者が別の失効操作を行います。

## 5. 必須ユーザーフロー

### 5.1 初回iPhone

1. 利用者が「このiPhoneで新しく始める」を選択する。
2. 復旧制限を確認する。
3. OS標準Local Authenticationを完了する。
4. User Scope、Device Identity、分離鍵をtransaction外の安全な領域で生成・読戻しする。
5. 公開メタデータを永続化し、整合性を再検証する。
6. すべて成功した場合だけMembershipを`established`にする。
7. 失敗時は空DBや別ScopeへFallbackせず、診断可能な利用不可状態を表示する。

### 5.2 新Mac追加

1. Macが「iPhoneに追加する」を選択する。
2. iPhoneが追加要求を発見し、端末種別と一時的な要求情報を表示する。
3. 両端末にSASを表示する。
4. 両端末が一致を明示確認する。
5. iPhoneがLocal Authentication後に追加を承認する。
6. 署名付きBootstrap EnvelopeをMacへ配送する。
7. MacがKeychain保存・読戻しと全検証を完了する。
8. 両端末がMembership、Pairing、Trust完了を確認する。
9. iPhone上で、このMacをPrimary Macにするか明示選択する。

### 5.3 既存Macから新iPhone追加

1. Macが現在`trusted`かつMembership Keyを利用可能であることを確認する。
2. 新iPhoneは「既存のユーザー領域に追加」を選択する。
3. 5.2と同じ対面SAS、両側確認、承認側Local Authenticationを行う。
4. 新iPhoneを新しいDevice IdentityとしてBootstrapする。
5. 旧iPhoneのIdentity、Primary Mac割当、未ACK状態を新iPhoneへ付け替えない。
6. 必要なデータ再同期、車両対応、旧端末失効はそれぞれ別の明示操作とする。

### 5.4 端末失効

1. 端末一覧で対象を選択する。
2. 失効の効果と、遠隔消去ではないことを表示する。
3. Local Authentication後に失効する。
4. 対象Peerへの接続、転送、ACK、鍵配送を即時停止する。
5. 失効結果と未到達Peerの有無を表示する。
6. 対象がPrimary Macの場合は、Primary不在状態を明示し、自動で別Macを選ばない。

### 5.5 Primary Mac交換

1. 新MacをMembershipへ追加し、PairingとTrustを完了する。
2. 対象iPhoneで旧Primary Macと新Macを表示する。
3. 未転送・未ACK Sessionと旧Mac不在時の影響を表示する。
4. iPhoneでLocal Authentication後に切替を確定する。
5. 単一transactionで新しいActive割当を公開する。
6. 旧Macへの新規ログDeliveryを作成しない。

## 6. 状態と遷移条件

既存設計のDB状態集合を維持し、製造担当が便宜的なBoolean一つへ統合しないことを要求します。

| 状態軸 | 必須状態／条件 |
|---|---|
| Local Membership | `unprovisioned` -> `bootstrap_pending` -> `established`。異常時は`blocked`。検証未完了で`established`へ進めない |
| Peer Membership Verification | `pending` -> `verified`または`rejected`。SAS一致だけで`verified`へ進めない |
| Pairing | `pending_local_confirmation`、`pending_peer_confirmation`、`paired`、`unpaired`。Local Membership establishedかつPeer verifiedだけが`paired`になれる |
| Trust | Pairingと分離し、失効後は新規通信を許可しない。自動再Trustしない |
| Primary Mac Assignment | iPhoneごとにActiveを最大1件とし、履歴を上書き・削除しない |

中断、再起動、重複要求、古いnonce、古いCredential ID、古いTrust generation、古いIdentityへのEnvelopeは安全に拒否または隔離します。失敗を成功扱いに収束させず、保存済みデータも削除しません。

## 7. 画面製造要件

Device Membershipは、HOME画面やPID取得・保存画面へ埋め込まず、各Platformで独立した別画面として製造します。HOMEにはMembershipの設定操作、端末一覧、SAS、失効、Primary Mac交換を配置しません。HOMEから別画面への導線を設ける場合も、状態を簡潔に示す入口までとし、Membership業務をHOME上で完結させません。

Membership画面の具体的なNavigation階層、Settings配下に置くか独立した端末管理機能として置くか、sheet／full-screen／window／detail paneの選択は、Platform別画面設計で確定します。iOSとmacOSの画面構成は共有せず、それぞれの利用可能領域と標準Navigationに合わせます。

### 7.1 iOS

- 初回作成／既存Membership参加の選択
- 復旧制限の確認
- 新端末要求一覧と承認
- SAS表示と一致／不一致操作
- Pairing済み端末一覧
- 端末詳細、役割、Membership／Pairing／Trust／Primary状態
- 失効確認
- Primary Mac選択・交換と未ACK警告
- MembershipまたはKeychain利用不可状態

### 7.2 macOS

- iPhoneへの参加要求開始
- 新iPhone追加の承認
- SAS表示と一致／不一致操作
- Pairing済み端末一覧
- 端末詳細、Membership／Pairing／Trust状態
- 失効確認
- Primary Macに指定された状態と、指定解除後の状態
- iPhoneアプリが開いていない、Local Network拒否、Membership／Keychain利用不可の案内

iOSとmacOSは別Viewツリー、別Navigation／Window構成で製造します。共有できるのはApplication状態、操作境界、表示専用値、非レイアウト資産だけです。画面からKeychain、GRDB、Network.frameworkを直接操作しません。

初期画面はApple標準UI部品を中心とした最小構成とし、端末名を認証根拠のように強調しません。Dynamic Type、VoiceOver、Keyboard、Focus、エラー読上げを各Platformで確認します。

## 8. 製造段階

### Stage A: 技術成立性確認

次を独立した検証成果物として提出してください。

1. iOS／macOS双方でのIdentity Signing、Identity Key Agreement、TLS Identityの用途分離。
2. Apple標準APIだけでのTLS Identity鍵、自己発行証明書、Key Usage／Extended Key Usage、Keychain保存、Network.framework相互TLSへの投入。
3. Secure Enclaveで利用できる鍵種別と、利用不可端末でのThisDeviceOnly Keychain fallback。
4. Local Authenticationの成功、キャンセル、失敗、Lockout、アプリ再開時の状態。
5. SASの標準化方式、桁数、試行上限、timeout、中断後の新nonce／ephemeral key生成。
6. Membership Keyと用途別限定鍵の署名付きWrapped Envelope、recipient binding、Replay拒否、Keychain保存・読戻し。
7. ルート鍵を追加端末へ配送しないことを確認できる鍵目録。
8. Identity鍵喪失、DBだけの復元、OS再インストール相当時に旧Identityを再利用しない挙動。

Stage Aは技術Spike、単体／結合テスト、検証報告までです。Fake、Simulator、ローカル証明書だけで実端末相互TLS成立と報告しません。

### Stage B: Membership基盤製造

Stage Aの成立条件が承認された後だけ開始します。

Stage Bの製造優先度は中です。HOME画面とPIDデータ取得・ローカル保存の高優先作業を侵食しない計画単位とし、それらの完了条件をMembership未実装だけでblockedにしません。ただし、Membership未確立のままPairing／同期を仮認証で有効化してはなりません。

- Domain: Membership、Device Identity、Trust、失効、Primary Macの純粋な状態と規則
- Domain Repository: Identity鍵、Membership Bootstrap、Peer、Trust、Primary割当の能力境界
- Application: 初回作成、新端末追加、両側確認、Bootstrap、失効、Primary交換のUse Caseと画面状態
- Data: Keychain／Secure Enclave、GRDB、Network.framework／Bonjourの具象Adapter
- Platform/iOS: 7.1のiOS専用画面
- Platform/macOS: 7.2のmacOS専用画面
- App: Platform別Composition Rootでの具象依存生成だけ

全ての新規・変更Swift宣言、initializer、メソッド、privateメソッドへSwift DocCを付けます。DomainとApplicationはSwiftUI、SwiftData、GRDB、UIKit、AppKitをimportしません。

### Stage C: Pairing／同期への接続

Membership established、Peer verified、Pairing paired、Trust trustedが成立した場合だけ、既存同期設計のInventory、Logical Change、Delivery、車両／Chunk同期へ接続します。Stage B完了だけで同期全体を完成扱いにしません。

## 9. 初期版対象外

- Account Membership Credential発行サーバー
- Sign in with AppleだけによるMembership確立
- 復旧コード
- 全信頼済み端末紛失後の既存Scope復旧
- 遠隔消去
- オフライン紛失端末への即時失効保証
- 端末名、Apple Account名、メール、Bluetooth名によるMembership判定
- User Scope UUIDの手入力・共有
- 旧Device Identityの新端末への移植
- ルート鍵の全端末共有
- ArchiveからのMembership自動復旧
- 初期版の削除伝播
- Membership未確立状態での車両、Digest、Session、Chunk同期

## 10. 必須テストと受入条件

### 10.1 Domain／Application

- 最初の端末がMacの場合、新規User Scope作成を拒否する。
- 初回iPhoneの全永続化が成功するまで`established`にならない。
- SAS片側確認、SAS不一致、Local Authentication失敗では承認しない。
- Bootstrap Envelopeの保存・読戻し前に`established`にならない。
- ルート鍵を配送対象として指定できない。
- 信頼済みMacから新iPhoneを新Identityとして追加できる。
- 信頼済み端末0台では既存Scopeへ参加できない。
- 失効Peerからの接続、変更、ACK、鍵配送を拒否する。
- 失効Peerを自動Trustしない。
- 最後の信頼済み端末を通常のPeer失効操作で失効できない。
- 旧Mac不在でもPrimary Macを交換できる。
- 同一iPhoneにActive Primary Macを2台設定できない。
- Primary交換で旧MacのTrustや保存済みデータを自動削除しない。
- stale callback、重複tap、再起動、古いnonce、古いTrust generationが状態を巻き戻さない。

### 10.2 Data／Security

- User Scope、Device Identity、Key Version、Fingerprintの不一致を拒否する。
- Signing、Agreement、TLS各鍵を別用途として生成・保存・検証する。
- 秘密鍵と平文対称鍵をGRDBへ保存しない。
- Membership Keyと用途別限定鍵を別Purpose／別Keychain itemとして扱う。
- recipient、Purpose、Version、Trust generation、nonce不一致のEnvelopeを拒否する。
- Replay、改ざん、未知Versionを拒否または隔離し、元bytesを自動削除しない。
- DBだけが復元されIdentity鍵がない場合、空DBへFallbackせず利用不可にする。
- 失効済みPeerをDB制約とRepositoryの両方で配送対象にできない。
- Migration失敗時にrollbackし、既存DBを削除しない。

### 10.3 Platform

- iOSとmacOSを別画面として確認する。
- Membership操作がHOMEまたはPID取得・保存画面へ埋め込まれていないことを確認する。
- HOMEから導線を設ける場合、Membershipの別画面へ遷移し、HOME上でSAS、端末失効、Primary Mac交換を実行できないことを確認する。
- iPhone初回作成、Mac追加、新iPhone追加、失効、Primary交換を各Platformの対象フローで確認する。
- SAS不一致、timeout、Local Authenticationキャンセル、Local Network拒否、Peer不在、Keychain利用不可を確認する。
- 端末失効画面が遠隔消去と誤認させない。
- 全端末紛失時の復旧不可を初期設定で確認できる。
- Dynamic Type、VoiceOver、macOS Keyboard／Focusを確認する。

## 11. 検証と証拠の区分

完了報告は次を混同しません。

| 証拠 | 証明できる範囲 |
|---|---|
| 静的検査／構造検証 | 配置、依存方向、禁止import、DocC等 |
| 単体テスト | 状態規則、失効、冪等性、拒否条件 |
| Fake／Preview | 画面Stateの表現。実暗号・実通信の成立は証明しない |
| iOS Simulator | 対象Simulator上のbuild／フロー。Secure Enclaveや実端末相互通信の証明にしない |
| macOS build／local test | 対象Mac上のbuild／ローカル挙動。iPhone実端末成立の証明にしない |
| iPhone／Mac実端末相互検証 | 対象OS、署名、Keychain、Local Authentication、Local Network、TLS相互通信の成立 |
| ユーザー目視確認 | iOS／macOS各画面の最終レイアウト承認 |

製造完了時は`Scripts/validate_structure.sh`、関連単体／結合テスト、macOS build、iOS Simulator buildを実行します。Swift、永続化、同期契約を変更した場合はDocC、設計文書、Persistence契約の検査も実行します。実端末、実ネットワーク、画面目視を実行していない場合は未検証として明記します。

## 12. 製造担当の完了報告

次だけを簡潔に報告してください。

1. 実装したStageと変更ファイル。
2. 確定した技術Version仕様と、その根拠。
3. 実行した検証と結果。
4. Simulator、実端末、目視確認を分離した証拠。
5. 未検証事項とHard Gate。
6. 既存データ、鍵、DB、Chunkを削除していないこと。

Stage Aが未成立の場合は、Stage BまたはCへ進まず、失敗した成立条件、再現手順、安全な停止状態、次の判断事項を報告します。仮Identity、平文Fallback、無条件証明書許可、SASだけのMembership成立でHard Gateを迂回しません。
