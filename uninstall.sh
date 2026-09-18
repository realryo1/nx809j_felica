#!/system/bin/sh
# Bind mounts drop on reboot. Only persistent extra is nci-update.
rm -f /data/vendor/nfc/libnfc-nci-update.conf
rm -f /data/local/tmp/felica_cfg.log /data/local/tmp/felica_cfg_svc.log
