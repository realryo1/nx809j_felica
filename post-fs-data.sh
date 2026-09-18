#!/system/bin/sh
# Factory ztecfg is GEN_JP. EvoX variantid falls back to GEN_NON_EEA and
# NFC HAL then loads non-FeliCa FW (no Type-F card emulation).
MODDIR=${0%/*}
LOG=/data/local/tmp/felica_cfg.log
echo "start $(date)" > "$LOG"

resetprop persist.vendor.custom.variant.id GEN_JP
resetprop persist.st_nfc_felica_ese 1
resetprop persist.st_nfc_felica_fsi 1
resetprop persist.vendor.nfc.config_file_name libnfc-hal-st_felica.conf
echo "props $(getprop persist.vendor.custom.variant.id)" >> "$LOG"

# Do not bind libnfc-nci_felica.conf (HOST_LISTEN 0x7 steals F to host).
# JNI RoutingManager reads these from nci-update, not HAL conf.
UPD=/data/vendor/nfc/libnfc-nci-update.conf
if [ -d /data/vendor/nfc ]; then
  cat > "$UPD" <<'EOF'
HOST_LISTEN_TECH_MASK=0x3
DEFAULT_NFCF_ROUTE=0x86
DEFAULT_SYS_CODE_ROUTE=0x86
EOF
  chown nfc:nfc "$UPD"
  chmod 644 "$UPD"
  chcon u:object_r:vendor_nfc_vendor_data_file:s0 "$UPD" >>"$LOG" 2>&1
  echo "nci_update ok" >> "$LOG"
fi

# Do not touch /system/app. mfm looks at /product/etc/felica first.
# cfgs live in $MODDIR/felica so Magic Mount does not create /system/etc/felica.
if [ ! -f /product/etc/felica/common.cfg ]; then
  umount /product/etc 2>/dev/null
  mkdir -p /dev/felica_cfg/upper/felica /dev/felica_cfg/work
  cp -f "$MODDIR/felica/"*.cfg /dev/felica_cfg/upper/felica/
  chmod 644 /dev/felica_cfg/upper/felica/*.cfg
  chcon -R u:object_r:system_file:s0 /dev/felica_cfg/upper >>"$LOG" 2>&1
  if mount -t overlay overlay -o "lowerdir=/product/etc,upperdir=/dev/felica_cfg/upper,workdir=/dev/felica_cfg/work" /product/etc >>"$LOG" 2>&1; then
    echo overlay_ok >> "$LOG"
  else
    echo overlay_failed >> "$LOG"
  fi
else
  echo "cfg already present" >> "$LOG"
fi
echo "done $(date)" >> "$LOG"
