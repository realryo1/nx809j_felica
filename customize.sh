#!/system/bin/sh
# KernelSU / Magisk zip install. Do not overlay /system/app.
SKIPUNZIP=0
ui_print "- NX809J FeliCa 1.0"
ui_print "- GEN_JP + felica cfg + Type-F listen. No APK overlay."

if [ -d /data/adb/modules/nx809j_felica_cfg ] && [ ! -f /data/adb/modules/nx809j_felica_cfg/remove ]; then
  touch /data/adb/modules/nx809j_felica_cfg/remove
  ui_print "- old nx809j_felica_cfg will be removed on reboot"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/tools/patch_jni.py" 0 0 0755
