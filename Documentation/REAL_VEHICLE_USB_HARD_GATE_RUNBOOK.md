# USB実車接続Hard Gate実行手順

## 1. 目的と現在地

本手順は、macOSとPrimary USB Adapterの組だけを対象に、`OBD_CAN_COMMUNICATION_RUNTIME_DESIGN.md`のHG-01、HG-04、HG-07、HG-08、HG-09、HG-10に必要な証拠を安全に採取するための実行票です。BluetoothとRaw CANは開発中であり、本手順では有効化も検証もしません。

2026-07-19の準備時点ではUSB serial endpointを検出できていません。Adapter model、firmware、serial endpoint、baud／flow control、driver、車両、イグニッション状態が未確定のため、exact command bytesを推測していません。Productionは引き続き`Unavailable`であり、この票の承認だけで製品接続が自動的に有効になることはありません。

## 2. 実行前に利用者が提示する情報

- Adapterの製品名と型番
- Adapterまたはvendor utilityで確認したfirmware version
- USB cableがAdapter一体か、別売り変換器か。変換器がある場合は製品名と型番
- 対象MacのmacOS versionとApple silicon／Intel
- 車両のメーカー、車種、年式。VIN／車台番号は記載しない
- イグニッションON・エンジン停止、またはエンジン始動中のどちらで行うか
- 車両が安全に停車し、Pレンジ／パーキングブレーキの状態であること
- Adapter／車両の一次資料またはvendor transcriptの所在

## 3. 承認前のread-only事前確認

1. `Scripts/prepare_real_vehicle_usb_gate.sh`を実行する。
2. USB serial候補数が1件であることを確認する。0件または複数件なら送信へ進まない。
3. Adapter model／firmwareと一次資料を照合する。
4. serial open条件、baud、data bits、parity、stop bits、flow control、line endingを資料とAdapter単体transcriptで確定する。
5. Adapter単体確認と車両向けOBD Requestを別の承認単位にする。
6. exact bytesを`VersionedELMCommandAllowlist`の対象model／firmware／mode限定entryとgolden testへ固定する。
7. Production compositionが`Unavailable`のままであることを確認し、専用の承認済みDevelopment実行経路だけで検証する。

## 4. 実車アクセス承認要求

### 目的

[今回確認する事実。HG番号と、Transport／Adapter／車両のどの事実を確認するかを記載]

### 対象構成

- App build／commit: [実行直前のcommit SHA、configuration、署名]
- Platform／OS: [macOS version]
- Device: [Mac model、CPU。ユーザー名や端末固有IDは記載しない]
- Adapter: [vendor、model]
- Firmware: [実機から確認したversion]
- Transport: USB serial [driver、endpointは証拠保存時にmask]
- 車両: [メーカー、車種、年式。VIN／車台番号は記載しない]
- イグニッション／エンジン状態: [明示]

### 実行する操作

1. read-only事前確認結果と物理構成を照合する。
2. 承認済みserial条件で対象endpointを1回openする。
3. 下記の型付きRequestだけを固定順序、固定回数で送信する。
4. Raw responseを暗号化された検証用保存境界へ保持し、通常ログには出さない。
5. 成否にかかわらず新規送信を止め、Transportをcloseする。

### 送信予定

- 型付きRequest: [Adapter単体制御と`OBDDiagnosticRequest`を一件ずつ列挙]
- exact bytes／ASCII: [一次資料とgolden transcriptで確定した値。未確定のまま承認依頼しない]
- Host→Adapter制御か、Adapter経由のOBD Requestか: [各Requestごとに明示]
- 根拠資料／transcript: [vendor一次資料、版、参照箇所、事前Adapter単体transcript]
- 送信順序: [固定順序]
- 最大回数: [Requestごとの上限。自動再試行なしを既定とする]
- 最小間隔: [資料と実測に基づく値]
- 最大実行時間: [全体deadline]

### 送信しない操作

- ECU reset
- DTC消去
- diagnostic write／coding
- CAN frame送信／inject／replay
- 任意command
- Raw CAN monitor
- 承認票にないAdapter初期化、capability probe、再試行

### 取得・保存する情報

- App build／commit、OS、Mac model、Adapter model、firmware、Transport kind
- 各Requestの型、allowlist version、送信sequence、monotonic時刻、結果分類
- exact送信bytesとRaw responseは暗号化された検証用evidenceだけへ保存
- open／close、timeout、disconnect、queue高水位／drop、保存成否
- マスク対象: VIN、車台番号、ユーザーID、端末固有ID、USB serial、endpoint path、Adapter固有address、通常ログ上のrequest／response payload

### 停止条件

- timeout
- 想定外応答、unknown status、malformed framing
- disconnect、endpoint変化、Adapter identity不一致
- queue高水位／drop
- DB／暗号化／書込／readback失敗
- ユーザーによる停止要求
- 車両警告灯、異音、異臭、発熱、発煙、予期しない車両挙動

### 緊急停止方法

1. アプリの「停止」を1回押し、新規Requestを禁止する。
2. 応答を待たずTransportをcloseする。
3. closeを確認できない、または車両側異常がある場合はAdapterのUSBをMac側から物理切断する。
4. 車両側異常が継続する場合は車両メーカーの安全手順に従い、追加試験を行わない。

### 承認範囲

この1回、この構成、このcommand集合、この最大時間だけ。変更・追加・再試行には再承認を求める。

承認者: [氏名または管理上の識別子]

承認日時: [timezone付き]

承認文: 「上記の対象構成、送信予定、停止条件、最大回数、最大実行時間に限り、1回の実車アクセスを承認します。」

## 5. 実行直前判定

次の全項目がYesでなければ実行しません。

- [ ] Adapter model／firmwareが一次資料およびallowlist対象と完全一致する
- [ ] USB endpointが1件で、承認後に差し替わっていない
- [ ] serial条件とdriver／sandbox／署名条件が確定している
- [ ] exact bytes、順序、回数、間隔、deadlineがgolden testと一致する
- [ ] Adapter単体制御と車両向けOBD Requestが区別されている
- [ ] Raw CAN、Bluetooth、任意command、自動再試行が実行経路から到達不能である
- [ ] 暗号化保存、readback、容量、queue、drop、停止操作が事前test済みである
- [ ] 車両が安全に停車し、緊急物理切断へ手が届く
- [ ] 上記承認文をこの構成について取得している

## 6. 実行後のHard Gate判定

成功した一回の通信だけで全Hard Gateを完了にしません。列挙／open／双方向通信、detach、再接続、timeout、想定外応答、queue／drop、sandbox／署名、Adapter identity、車両再識別をそれぞれ証拠化します。Development buildの成功をRelease／TestFlight／配布署名の成立と扱いません。BluetoothとRaw CANは引き続き`blocked`です。

## 7. 2026-07-19 Adapter単体識別証拠

車両OBDコネクタを物理的に外し、USBだけを対象Macへ接続した状態で実施しました。USB serial、endpoint path、車台番号は記録していません。

- App／source commit: `3574ffb5767143cc52f2b05f3dc349f003323f3a`。未コミット作業ツリーを含むDevelopment一回限定probe
- Platform: macOS 26.5.2、Apple silicon
- USB descriptor: Product `OBDLink EX`、Vendor `ScanTool.net LLC`、VID `0x0403`、PID `0x6015`
- Serial条件: 115200 bps、8 data bits、no parity、1 stop bit
- Adapter label: OBDLink EX、MODEL EX101、OBD Solutions LLC
- Hardware response: `OBDLink EX r2.7.1`
- Firmware response: `STN2232 v5.10.3`
- 実行時間: 1秒未満

承認済みtranscriptは次の固定順序です。

| 型付きRequest | exact ASCII | exact Hex | 分類 | 結果 |
|---|---|---|---|---|
| `adapterInputBoundaryClear` | `??\r` | `3F 3F 0D` | Host-to-Adapter | prompt確認 |
| `adapterInitializationReset` | `ATZ\r` | `41 54 5A 0D` | Host-to-Adapter | `ELM327 v1.4b`、prompt確認 |
| `adapterHardwareIdentification` | `STDI\r` | `53 54 44 49 0D` | Host-to-Adapter | `OBDLink EX r2.7.1`、prompt確認 |
| `adapterFirmwareIdentification` | `STI\r` | `53 54 49 0D` | Host-to-Adapter | `STN2232 v5.10.3`、prompt確認 |

各Requestは1回だけ送信し、自動再試行は行っていません。車両bus向けOBD Request、ECU reset、DTC消去、diagnostic write、CAN frame送信、Raw CAN monitor、serial取得、factory reset、firmware更新、NVM書込みは0件です。Transportは識別完了後に正常closeしました。

この証拠により、対象Mac上のUSB列挙、serial open、対象Adapterとの双方向Host通信、hardware／firmware identityを確認しました。車両OBD応答、Adapterが生成する車両bus frame、切断中のinflight処理、再接続、queue／drop、配布署名／sandbox、Production App統合は未確認です。したがってHG-01とHG-04は部分通過であり、Production Transportは引き続き`blocked`です。
