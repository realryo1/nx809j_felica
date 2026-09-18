# NX809J FeliCa

NX809J（RedMagic 10 Pro 日本向け）の Evolution X で、おサイフケータイの **かざし（Type-F CE）** まで含めて動かす KernelSU モジュール。APK の `/system/app` overlay はしない（起動停止する）。

確認済み: 再起動後に Rakuten Mini が Suica を読む。3cm 程度でも認識。

## 入れるもの

| 層 | 内容 |
| --- | --- |
| persist | `GEN_JP`、`persist.st_nfc_felica_ese/fsi=1`、HAL を `libnfc-hal-st_felica.conf` |
| cfg | stock の `common.cfg` / `mfm.cfg` / `mfs.cfg` を `/product/etc/felica/` へ |
| CE | AOSP JNI が eSE の Type-F listen を落とすのを、`libnfc_nci_jni.so` の 2 命令だけ直して zygote ns に bind |
| 032016 | ユーザーおサイフから Play ストアが見えるよう `force-queryable` |

前提: eSE1（OMAPI）が生きていること。TEST の eSE1 イメージはそのまま。古い `nx809j_felica_cfg` とは同時に入れない（この zip を入れると再起動で remove する）。

## 入れ方

中身を zip にする（`.git` は入らない）:

```text
python tools/pack.py
```

KernelSU で `nx809j_felica-1.0.zip` をインストールして再起動。または:

```text
ksud module install nx809j_felica-1.0.zip
```

ログ: `/data/local/tmp/felica_cfg.log` と `felica_cfg_svc.log`。

かざし確認: `dumpsys nfc` に `NFC_F_PASSIVE_LISTEN_MODE` と `TECHNOLOGY_F … 0x86`。

## やらないこと

- `/system/app` への APK overlay
- `libnfc-nci_felica.conf` の bind（`HOST_LISTEN_TECH_MASK=0x7` は F を host に盗む）
- HAL CHECK パッチ、eSE ファームの推測書き換え

## JNI パッチ

対象: Evolution X 17 の `/apex/com.android.nfcservices/lib64/libnfc_nci_jni.so`（RoutingManager::updateEeTechRouteSetting）。apex の ROM 更新後は `tools/patch_jni.py` で作り直す。

```text
python tools/patch_jni.py path/to/libnfc_nci_jni.so -o jni/libnfc_nci_jni.so
```

- `0x1634cc`: F ルート一致時に `lf_protocol==0` でも F を載せる
- `0x1634dc`: `OFFHOST_LISTEN_TECH_MASK` の AND で F を消さない

apex は zygote の mount ns にだけ見える。`su` からの bind では NfcService に届かない。
