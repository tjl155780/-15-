#!/system/bin/sh
# 卸载时：解除 bind 挂载（原厂文件自动恢复）+ 还原 persist ini + 清掉 DSCP 规则
for SRC in \
    /odm/firmware/tp/infiniti/vnd_custom_config_main.xml \
    /system/odm/firmware/tp/infiniti/vnd_custom_config_main.xml \
    /mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini ; do
    if mount | grep -q " $SRC "; then
        umount "$SRC" 2>/dev/null
    fi
done

# 还原 persist ini 原厂备份（有备份才动）
if [ -s /data/adb/op15_lowlat/ini_WCNSS_qcom_cfg.ini_original.cfg ] \
   && [ -f /mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini ]; then
    cat /data/adb/op15_lowlat/ini_WCNSS_qcom_cfg.ini_original.cfg \
        > /mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini 2>/dev/null
fi

GAME_UID=$(stat -c %u /data/user/0/com.tencent.tmgp.sgame 2>/dev/null)
case "$GAME_UID" in ""|*[!0-9]*) GAME_UID="" ;; esac
if [ -n "$GAME_UID" ] && [ "$GAME_UID" -ge 10000 ]; then
    for _chain in OUTPUT POSTROUTING; do
        while iptables -t mangle -D "$_chain" -m owner --uid-owner "$GAME_UID" \
            -j DSCP --set-dscp-class EF 2>/dev/null; do :; done
    done
fi
exit 0
