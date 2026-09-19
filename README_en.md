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

## Trade-offs

Choosing tap means giving up hiding.

| Cost | What it is |
| --- | --- |
| JNI left on zygote | Type-F listen survives later NFC restarts. The `/data` `.so` overlay is visible to GMS / DroidGuard. 1.1+ unmounted it for DEVICE; tap then died after reboot. Wipe still left DEVICE at BASIC, so the ROM side (fingerprint split, etc.) already fails DEVICE on its own |
| Play Store `force-queryable` | User-installed Osaifu can see Play. Every app can see that Play is installed. A Play self-update can drop the flag until the next boot (`(032016)`). Uninstalling the module leaves the 4 APKs and this flag |
| TEST eSE1 + KernelSU | Mainline ROM has no `ISecureElement/eSE1`. The JNI patch is for this Evolution X 17 apex. Overlaying `/system/app` hangs boot on this device |

Forcing routes toward eSE1 can leave Google Pay Type-A HCE on host or pull it onto eSE. FeliCaLock is not on stock, so it is not included.

## If you were creating a Japan-oriented Evolution X build

Stock Osaifu is a system app, so Play `force-queryable` would not be needed. Overlaying `/system/app` after the fact with KernelSU hangs boot on this device. `FLAG_SYSTEM` therefore has to be baked into the image.

If the ROM baked the following into super / product / the NFC apex, this module would not be needed.

| If the ROM | then |
| --- | --- |
| Restores odm `ISecureElement/eSE1` and unstops the HAL on JP only (keep the global mask) | OMAPI without the TEST zip |
| Ships the 4 APKs in `/system/app` or `/product/app` at build time | `FLAG_SYSTEM`. No Play `force-queryable`. `(032016)` goes away |
| Puts `common.cfg` `00000011,eSE1` on `/product/etc/felica` | `(030204)` goes away |
| Defaults the JP SKU to `GEN_JP` and `libnfc-hal-st_felica.conf` (do not ship `HOST_LISTEN=0x7`) | Type-F firmware. No per-boot `resetprop` |
| Fixes `RoutingManager` in source and ships it in the NFC apex | No zygote bind. No `/data` `.so` overlay |
| Does all of the above | Issuance and tap can work with no KernelSU module. `st54j*.ko` is already in `vendor_boot` |

Baking in FeliCa and passing Play Integrity DEVICE are separate.

| If | then |
| --- | --- |
| Only FeliCa is baked on the current 17/09 base | The module can go. Tap and Google login look like stock. DEVICE only loses the extra wounds this module adds (zygote bind, Play visible to every app, `resetprop`). The 17/09 fingerprint split (mustang Canary vs NX809J) stays, so DEVICE likely still fails |
| The 03/09-class Integrity spoof is restored and FeliCa is baked | DEVICE and tap can coexist. 03/09 already got BASIC+DEVICE with KernelSU in the kernel. STRONG still fails while unlocked |
| KernelSU is removed from the kernel | Not required for FeliCa. It may help DEVICE, but it was not required on 03/09 |

Stock on this unit already did Suica at the gate with an unlocked bootloader and without BASIC. Tap itself does not require DEVICE.
