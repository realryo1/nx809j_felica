#!/system/bin/sh
# Bind mounts drop on reboot. nci-update is the only extra file to delete.
# User-installed FeliCa APKs and their data stay.
rm -f /data/vendor/nfc/libnfc-nci-update.conf
rm -f /data/local/tmp/felica_cfg.log /data/local/tmp/felica_cfg_svc.log
