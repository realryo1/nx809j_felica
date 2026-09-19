# NX809J FeliCa

NX809J（RedMagic 11 Pro 日本向け）の Evolution X で、おサイフケータイのかざし（Type-F CE）まで動かす KernelSU モジュール。

English: [README_en.md](README_en.md)

確認済み: 再起動後に Rakuten Mini が Suica を読む。3cm 程度でも認識。Google ログイン（032016）は Play ストアを `force-queryable` にして通す。

## 全体

| 層 | どこ | 状態 |
| --- | --- | --- |
| eSE1（OMAPI） | TEST イメージで VINTF 復元 | 動いた。本流 ROM へ戻す件は XDA |
| おサイフ 4 APK | この zip の `apk/`。起動時にユーザーインストール | `/system/app` overlay は使わない |
| Play ストア可視性 | 起動時に `force-queryable`（最大 5 回） | ユーザーおサイフから Play が見えないと Google ログインが `(032016)` |
| cfg + `GEN_JP` + Type-F JNI | この zip | 対象 |


## おサイフ 4 APK

実体は NX809J stock。

| zip 内 | package | 元 |
| --- | --- | --- |
| `apk/MobileFeliCaClient/MobileFeliCaClient.apk` | `com.felicanetworks.mfc` | `stock20-felica-system` |
| `apk/MobileFeliCaMenuMainApp/MobileFeliCaMenuMainApp.apk` | `com.felicanetworks.mfm.main` | `stock20-felica-system` |
| `apk/MobileFeliCaSettingApp/MobileFeliCaSettingApp.apk` | `com.felicanetworks.mfs` | `stock20-felica-data/mfs.apk`（system の SettingApp より新しい） |
| `apk/MobileFeliCaWebPluginBoot/MobileFeliCaWebPluginBoot.apk` | `com.felicanetworks.mfw.a.boot` | `stock20-felica-system` |

`FeliCaLock` と `MobileFeliCaWebPlugin` は NX809J stock に無いので入れない。

起動後、未インストールなら `mfc` → `mfs` → `mfw` → `mfm` の順で `pm install`（ユーザーアプリ）。既にあるパッケージは触らない（Suica データを残す）。Play だけ先に入っていると `MFC_ACCESS` が落ちることがある。そのときは Play 側を消して再起動し、このモジュールに入れさせる。

モジュールを外しても 4 APK は残る。Play の `force-queryable` も残る。

## この zip が入れるもの

| 内容 | 役割 |
| --- | --- |
| persist | `GEN_JP`、`persist.st_nfc_felica_ese/fsi=1`、HAL を `libnfc-hal-st_felica.conf` |
| cfg | stock の `common.cfg` / `mfm.cfg` / `mfs.cfg` を `/product/etc/felica/` へ |
| CE | AOSP JNI が eSE の Type-F listen を落とすのを、`libnfc_nci_jni.so` の 2 命令だけ直す。zygote に bind して残す（1.0） |
| 4 APK | `apk/` からユーザーインストール。`mfc` を先に入れる |
| 032016 | 起動時に Play ストアへ `force-queryable` を最大 5 回付ける。Play の自己更新で落ちたら次の起動で付け直す |

## 入れ方

[Releases](https://github.com/realryo1/nx809j_felica/releases) の `nx809j_felica-*.zip` を KernelSU に入れて再起動。

手元で固める場合:

```text
python tools/pack.py
ksud module install nx809j_felica-1.5.zip
```

ログ: `/data/local/tmp/felica_cfg.log` と `felica_cfg_svc.log`。後者に `apk ok` または `apk already`、`vending force-queryable ok`、`NFC_F_PASSIVE_LISTEN_MODE` があること。

かざし: `dumpsys nfc` に `NFC_F_PASSIVE_LISTEN_MODE` と `TECHNOLOGY_F … 0x86`。

## やらないこと

- `/system/app` への APK overlay
- `libnfc-nci_felica.conf` の bind（`HOST_LISTEN_TECH_MASK=0x7` は F を host に盗む）
- HAL CHECK パッチ、eSE ファームの推測書き換え
- Mini 用 AndroPlus APK の流用

## JNI パッチ

対象: Evolution X 17 の `/apex/com.android.nfcservices/lib64/libnfc_nci_jni.so`（RoutingManager::updateEeTechRouteSetting）。apex の ROM 更新後は `tools/patch_jni.py` で作り直す。

```text
python tools/patch_jni.py path/to/libnfc_nci_jni.so -o jni/libnfc_nci_jni.so
```

- `0x1634cc`: F ルート一致時に `lf_protocol==0` でも F を載せる
- `0x1634dc`: `OFFHOST_LISTEN_TECH_MASK` の AND で F を消さない

apex の `.so` は `su` ns からは NfcService に届かない。zygote に bind して残す（1.0 と同じ）。NFC が後から起き直しても Type-F listen が残る。zygote から外すと再起動後のかざしが落ちる。

## 代償

かざしを優先した時点で、隠す側は捨てている。

| 代償 | 内容 |
| --- | --- |
| JNI を zygote に残す | NFC が後から起き直しても Type-F listen が残る。代わりに `/data` の `.so` overlay が GMS / DroidGuard から見える。1.1 以降は DEVICE 用に外して、再起動後のかざしが死んだ。wipe 後も DEVICE は BASIC のままなので、ROM 側（fingerprint の食い違いなど）でも既に落ちている |
| Play を `force-queryable` | ユーザーおサイフから Play が見える。どのアプリからも Play の存在が見える。Play の自己更新でフラグが落ち、次の起動まで `(032016)` になり得る。モジュールを外しても 4 APK とこのフラグは残る |
| TEST の eSE1 と KernelSU | 本流 ROM では `ISecureElement/eSE1` が無い。JNI は Evolution X 17 のその apex 用。`/system/app` overlay はこの機種で起動停止する |

ルートを eSE1 に寄せるので、Google Pay の Type-A HCE は host に残ったり eSE に寄ったりする。FeliCaLock は stock にも無いので入れてない。

## もし Evolution X の日本向けビルドを作成するなら

stock ならおサイフは system アプリなので Play の `force-queryable` は不要。KernelSU で `/system/app` に後から足すとこの機種では起動停止する。だから `FLAG_SYSTEM` はイメージに最初から焼くしかない。

もし ROM が次を super / product / NFC apex に焼いたら、このモジュールは不要。

| もし ROM が | なら |
| --- | --- |
| JP だけ odm の `ISecureElement/eSE1` を戻し、HAL の `stop` を外す（グローバルは今どおりマスク） | TEST zip 無しで OMAPI |
| 4 APK をビルド時に `/system/app` か `/product/app` へ | `FLAG_SYSTEM`。Play の `force-queryable` は不要。`(032016)` も消える |
| `common.cfg` の `00000011,eSE1` を `/product/etc/felica` へ | `(030204)` は消える |
| JP SKU の既定を `GEN_JP` と `libnfc-hal-st_felica.conf` にする（`HOST_LISTEN=0x7` は載せない） | Type-F FW。起動ごとの `resetprop` は不要 |
| `RoutingManager` をソースで直し、NFC apex に入れる | zygote bind は不要。`/data` の `.so` overlay も無い |
| 上まで焼く | KernelSU モジュール無しでも発行とかざしは成立し得る。`st54j*.ko` は既に `vendor_boot` にある |

FeliCa を焼くことと Play Integrity DEVICE は別。

| もし | なら |
| --- | --- |
| 今の 17/09 ベースに FeliCa だけ焼く | モジュールは消せる。かざしと Google ログインは stock に近い。DEVICE はこのモジュールが足している傷（zygote bind、Play 全公開、`resetprop`）が無いだけ。17/09 の指紋（mustang Canary 対 NX809J）はそのままなので、DEVICE は通らない可能性が高い |
| 03/09 相当の Integrity spoof を戻したうえで FeliCa も焼く | DEVICE とかざしが両立し得る。03/09 は KernelSU 入りカーネルのままで BASIC+DEVICE が出ていた。STRONG は unlock のままでは出ない |
| KernelSU をカーネルから外す | FeliCa には不要。DEVICE の保険にはなるが、03/09 では必須ではなかった |

この機の stock は bootloader unlock・BASIC 無しでも Suica 改札は通っている。おサイフのかざし自体は DEVICE を要求しない。
