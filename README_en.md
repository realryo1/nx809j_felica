# NX809J FeliCa

KernelSU module that enables Osaifu-Keitai tap (Type-F card emulation) on Evolution X for the Japan NX809J (RedMagic 11 Pro).

日本語: [README.md](README.md)

Verified: after reboot, a Rakuten Mini reads Suica from this phone. It still works at about 3 cm. Google login (032016) works by making Play Store `force-queryable`.

## Overview

| Layer | Where | Status |
| --- | --- | --- |
| eSE1 (OMAPI) | VINTF restored in the TEST image | Works. Putting this back on the mainline ROM is an XDA matter |
| Osaifu-Keitai 4 APKs | `apk/` in this zip; installed as user apps at boot | Do not overlay `/system/app` |
| Play Store visibility | `force-queryable` at boot (up to 5 tries) | User-installed Osaifu cannot see Play otherwise → Google login `(032016)` |
| cfg + `GEN_JP` + Type-F JNI | This zip | In scope |

## Osaifu-Keitai 4 APKs

Binaries are from NX809J stock.

| In the zip | Package | Source |
| --- | --- | --- |
| `apk/MobileFeliCaClient/MobileFeliCaClient.apk` | `com.felicanetworks.mfc` | `stock20-felica-system` |
| `apk/MobileFeliCaMenuMainApp/MobileFeliCaMenuMainApp.apk` | `com.felicanetworks.mfm.main` | `stock20-felica-system` |
| `apk/MobileFeliCaSettingApp/MobileFeliCaSettingApp.apk` | `com.felicanetworks.mfs` | `stock20-felica-data/mfs.apk` (newer than the system SettingApp) |
| `apk/MobileFeliCaWebPluginBoot/MobileFeliCaWebPluginBoot.apk` | `com.felicanetworks.mfw.a.boot` | `stock20-felica-system` |

`FeliCaLock` and `MobileFeliCaWebPlugin` are not on NX809J stock, so they are not included.

After boot, if a package is missing, `pm install` it as a user app in this order: `mfc` → `mfs` → `mfw` → `mfm`. Already-installed packages are left alone (so Suica data stays). If only the Play Store copies were installed first, `MFC_ACCESS` can fail. Uninstall those Play copies, reboot, and let this module install them.

Uninstalling the module does not remove the 4 APKs. Play Store `force-queryable` also stays.

## What this zip applies

| Item | Role |
| --- | --- |
| persist | `GEN_JP`, `persist.st_nfc_felica_ese/fsi=1`, HAL config `libnfc-hal-st_felica.conf` |
| cfg | Stock `common.cfg` / `mfm.cfg` / `mfs.cfg` onto `/product/etc/felica/` |
| CE | AOSP JNI drops Type-F listen on eSE; patch two instructions in `libnfc_nci_jni.so`. Bind zygote and leave it (1.0 tap path) |
| 4 APKs | User-install from `apk/`. `mfc` first |
| 032016 | Set Play Store `force-queryable` at boot (up to 5 tries). Re-apply on the next boot if a Play self-update drops it |

## Install

Install the `nx809j_felica-*.zip` from [Releases](https://github.com/realryo1/nx809j_felica/releases) in KernelSU and reboot.

To pack locally:

```text
python tools/pack.py
ksud module install nx809j_felica-1.5.zip
```

Logs: `/data/local/tmp/felica_cfg.log` and `felica_cfg_svc.log`. The latter should contain `apk ok` or `apk already`, `vending force-queryable ok`, and `NFC_F_PASSIVE_LISTEN_MODE`.

Tap / CE: `dumpsys nfc` should show `NFC_F_PASSIVE_LISTEN_MODE` and `TECHNOLOGY_F … 0x86`.

## Do not

- Overlay APKs onto `/system/app`
- Bind `libnfc-nci_felica.conf` (`HOST_LISTEN_TECH_MASK=0x7` steals F onto the host)
- Patch HAL CHECKs, or rewrite eSE firmware by guesswork
- Reuse AndroPlus APKs meant for Rakuten Mini

## JNI patch

Target: Evolution X 17 `/apex/com.android.nfcservices/lib64/libnfc_nci_jni.so` (`RoutingManager::updateEeTechRouteSetting`). After an NFC apex ROM update, rebuild with `tools/patch_jni.py`.

```text
python tools/patch_jni.py path/to/libnfc_nci_jni.so -o jni/libnfc_nci_jni.so
```

- `0x1634cc`: on a matching F route, still load F even when `lf_protocol==0`
- `0x1634dc`: do not strip F with the `OFFHOST_LISTEN_TECH_MASK` AND

A bind from the `su` namespace never reaches NfcService. Bind zygote and leave it (same as 1.0) so later NFC restarts keep Type-F listen. Unmounting zygote drops tap after reboot.
