#!/system/bin/sh
# 1. variantidBin may overwrite GEN_JP with GEN_NON_EEA after post-fs-data.
# 2. AOSP NFC apex JNI skips Type-F listen when eSE reports lf_protocol=0.
#    Bind a patched libnfc_nci_jni.so into zygote's mount ns (apex is not
#    visible from the su ns bind).
# 3. Play Store force-queryable for user-installed mfm (032016).
MODDIR=${0%/*}
LOG=/data/local/tmp/felica_cfg_svc.log
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
ZYGOTE=$(pidof zygote64)
if [ -f "$JNI" ] && [ -n "$ZYGOTE" ]; then
  chcon u:object_r:system_lib_file:s0 "$JNI" >>"$LOG" 2>&1
  chmod 644 "$JNI"
  for p in /apex/com.android.nfcservices/lib64/libnfc_nci_jni.so /apex/com.android.nfcservices@*/lib64/libnfc_nci_jni.so; do
    [ -f "$p" ] || continue
    nsenter -t "$ZYGOTE" -m -- umount "$p" 2>/dev/null
    if nsenter -t "$ZYGOTE" -m -- mount --bind "$JNI" "$p" >>"$LOG" 2>&1; then
      echo "jni_bind $p" >> "$LOG"
    else
      echo "jni_bind_fail $p" >> "$LOG"
    fi
  done
else
  echo "jni skip zygote=$ZYGOTE file=$( [ -f "$JNI" ] && echo yes || echo no )" >> "$LOG"
fi

need_bounce=1
if dumpsys nfc 2>/dev/null | grep -q "NFC_F_PASSIVE_LISTEN_MODE"; then
  need_bounce=0
  echo "f listen already on" >> "$LOG"
fi

if [ "$need_bounce" = "1" ]; then
  echo "bounce nfc" >> "$LOG"
  svc nfc disable
  killall com.android.nfc 2>/dev/null
  sleep 2
  svc nfc enable
  sleep 6
fi

cmd nfc overwrite-routing-table 0 eSE1 eSE1 eSE1 eSE1 eSE1 >>"$LOG" 2>&1
dumpsys nfc 2>/dev/null | grep -E "SYSTEMCODE_FEFE|TECHNOLOGY_F|NFC_F_PASSIVE" >> "$LOG"

has_override() {
  dumpsys package com.android.vending 2>/dev/null | grep -q "forceQueryable=false (override=true)"
}

if has_override; then
  echo "vending override already true" >> "$LOG"
  echo "done $(date)" >> "$LOG"
  exit 0
fi

SESSION=$(pm install-create -r --force-queryable --user 0 -p com.android.vending 2>>"$LOG")
SESSION=$(echo "$SESSION" | sed -n "s/.*\[\([0-9][0-9]*\)\].*/\1/p")
if [ -z "$SESSION" ]; then
  echo "install-create failed" >> "$LOG"
  echo "done $(date)" >> "$LOG"
  exit 0
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
  echo "done $(date)" >> "$LOG"
  exit 0
fi

pm install-commit "$SESSION" >>"$LOG" 2>&1
echo "commit done n=$n $(date)" >> "$LOG"
