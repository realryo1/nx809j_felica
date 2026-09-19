#!/system/bin/sh
# 1. variantidBin may overwrite GEN_JP with GEN_NON_EEA after post-fs-data.
# 2. AOSP NFC apex JNI skips Type-F listen when eSE reports lf_protocol=0.
#    Bind patched libnfc_nci_jni.so into zygote, bounce NFC so it inherits,
#    then umount zygote / GMS / vending. Leaving the bind on zygote makes
#    DroidGuard see a /data overlay and DEVICE drops.
# 3. Bundled FeliCa APKs are user-installed (pm). Do not overlay /system/app.
# 4. Play Store force-queryable always. User-installed mfm cannot see
#    com.android.vending otherwise (032016 on Google login).
MODDIR=${0%/*}
LOG=/data/local/tmp/felica_cfg_svc.log
TMPAPK=/data/local/tmp/felica_apk
echo "start $(date)" > "$LOG"

i=0
while [ "$i" -lt 40 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i + 1))
done
sleep 5

resetprop persist.vendor.custom.variant.id GEN_JP
resetprop persist.st_nfc_felica_ese 1
resetprop persist.st_nfc_felica_fsi 1
resetprop persist.vendor.nfc.config_file_name libnfc-hal-st_felica.conf
echo "variant $(getprop persist.vendor.custom.variant.id)" >> "$LOG"

JNI="$MODDIR/jni/libnfc_nci_jni.so"

umount_jni() {
  target="$1"
  [ -n "$target" ] || return 0
  for p in /apex/com.android.nfcservices/lib64/libnfc_nci_jni.so /apex/com.android.nfcservices@*/lib64/libnfc_nci_jni.so; do
    nsenter -t "$target" -m -- umount "$p" 2>/dev/null
  done
}

bind_jni() {
  target="$1"
  tag="$2"
  if [ -z "$target" ]; then
    echo "jni skip $tag no pid" >> "$LOG"
    return 1
  fi
  ok=0
  for p in /apex/com.android.nfcservices/lib64/libnfc_nci_jni.so /apex/com.android.nfcservices@*/lib64/libnfc_nci_jni.so; do
    nsenter -t "$target" -m -- test -f "$p" || continue
    nsenter -t "$target" -m -- umount "$p" 2>/dev/null
    if nsenter -t "$target" -m -- mount --bind "$JNI" "$p" >>"$LOG" 2>&1; then
      echo "jni_bind $tag $p" >> "$LOG"
      ok=1
    else
      echo "jni_bind_fail $tag $p" >> "$LOG"
    fi
  done
  [ "$ok" = "1" ]
}

if [ -f "$JNI" ]; then
  chcon u:object_r:system_lib_file:s0 "$JNI" >>"$LOG" 2>&1
  chmod 644 "$JNI"
  ZYGOTE=$(pidof zygote64)
  bind_jni "$ZYGOTE" zygote
  echo "bounce nfc" >> "$LOG"
  svc nfc disable
  killall com.android.nfc 2>/dev/null
  sleep 2
  svc nfc enable
  sleep 6
  umount_jni "$ZYGOTE"
  echo "jni_umount zygote $ZYGOTE" >> "$LOG"
  for name in com.google.android.gms com.google.android.gms.unstable com.android.vending; do
    for pid in $(pidof "$name"); do
      umount_jni "$pid"
      echo "jni_umount $name $pid" >> "$LOG"
    done
  done
else
  echo "jni skip no file" >> "$LOG"
fi

cmd nfc overwrite-routing-table 0 eSE1 eSE1 eSE1 eSE1 eSE1 >>"$LOG" 2>&1
dumpsys nfc 2>/dev/null | grep -E "SYSTEMCODE_FEFE|TECHNOLOGY_F|NFC_F_PASSIVE" >> "$LOG"

# AndroPlus layout is system/app/<Name>/<Name>.apk (Magic Mount). That hung
# boot on NX809J erofs. Same folder names live under $MODDIR/apk and pm
# installs them as user apps. mfc first so mfm can get MFC_ACCESS.
install_user_apk() {
  pkg="$1"
  apk="$2"
  if [ ! -f "$apk" ]; then
    echo "apk missing $apk" >> "$LOG"
    return 1
  fi
  if pm path "$pkg" >/dev/null 2>&1; then
    echo "apk already $pkg" >> "$LOG"
    return 0
  fi
  mkdir -p "$TMPAPK"
  tmp="$TMPAPK/$(basename "$apk")"
  cp -f "$apk" "$tmp" || return 1
  chmod 644 "$tmp"
  echo "apk install $pkg" >> "$LOG"
  if pm install -r --user 0 "$tmp" >>"$LOG" 2>&1; then
    echo "apk ok $pkg" >> "$LOG"
    rm -f "$tmp"
    return 0
  fi
  echo "apk fail $pkg" >> "$LOG"
  rm -f "$tmp"
  return 1
}

APKDIR="$MODDIR/apk"
apk_fail=0
install_user_apk com.felicanetworks.mfc "$APKDIR/MobileFeliCaClient/MobileFeliCaClient.apk" || apk_fail=1
install_user_apk com.felicanetworks.mfs "$APKDIR/MobileFeliCaSettingApp/MobileFeliCaSettingApp.apk" || apk_fail=1
install_user_apk com.felicanetworks.mfw.a.boot "$APKDIR/MobileFeliCaWebPluginBoot/MobileFeliCaWebPluginBoot.apk" || apk_fail=1
install_user_apk com.felicanetworks.mfm.main "$APKDIR/MobileFeliCaMenuMainApp/MobileFeliCaMenuMainApp.apk" || apk_fail=1
pm grant com.felicanetworks.mfm.main com.felicanetworks.mfc.permission.MFC_ACCESS >>"$LOG" 2>&1
rmdir "$TMPAPK" 2>/dev/null
if [ "$apk_fail" -ne 0 ]; then
  echo "apk install FAILED" >> "$LOG"
fi

has_vending_override() {
  dumpsys package com.android.vending 2>/dev/null | grep -q "forceQueryable=false (override=true)"
}

ensure_vending_queryable() {
  SESSION=$(pm install-create -r --force-queryable --user 0 -p com.android.vending 2>>"$LOG")
  SESSION=$(echo "$SESSION" | sed -n "s/.*\[\([0-9][0-9]*\)\].*/\1/p")
  if [ -z "$SESSION" ]; then
    echo "install-create failed" >> "$LOG"
    return 1
  fi

  n=0
  fail=0
  for line in $(pm path com.android.vending); do
    apk=${line#package:}
    [ -f "$apk" ] || continue
    if [ "$n" -eq 0 ]; then
      split=base
    else
      split=$(basename "$apk" .apk)
    fi
    size=$(wc -c < "$apk" | tr -d " ")
    if ! pm install-write -S "$size" "$SESSION" "$split" "$apk" >>"$LOG" 2>&1; then
      fail=1
      break
    fi
    n=$((n + 1))
  done

  if [ "$fail" -ne 0 ] || [ "$n" -eq 0 ]; then
    echo "write failed n=$n" >> "$LOG"
    pm install-abandon "$SESSION" >>"$LOG" 2>&1
    return 1
  fi

  if ! pm install-commit "$SESSION" >>"$LOG" 2>&1; then
    echo "commit failed" >> "$LOG"
    return 1
  fi
  echo "commit done n=$n" >> "$LOG"
  return 0
}

v=0
while [ "$v" -lt 5 ]; do
  if has_vending_override; then
    echo "vending force-queryable ok" >> "$LOG"
    echo "done $(date)" >> "$LOG"
    if [ "$apk_fail" -ne 0 ]; then
      exit 1
    fi
    exit 0
  fi
  echo "vending force-queryable missing, try $v" >> "$LOG"
  ensure_vending_queryable
  sleep 3
  v=$((v + 1))
done

echo "vending force-queryable FAILED" >> "$LOG"
echo "done $(date)" >> "$LOG"
exit 1
