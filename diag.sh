#!/system/bin/sh
# 一加15·王者低延迟引擎 自检 —— su 后直接 sh diag.sh 运行
MODDIR=${0%/*}
[ -f "$MODDIR/core.sh" ] || { echo "ERROR: core.sh 缺失"; exit 1; }
export OPL_NO_AUTORUN=1
. "$MODDIR/core.sh"
find_resetprop

echo "════════════════════════════════════════"
echo " 一加15·王者低延迟引擎 状态自检"
echo "════════════════════════════════════════"
echo "[1] 环境"
_bs="缺失!"
[ -s "$BASE" ] && _bs="OK, $(wc -l < "$BASE") 行"
_tier="极限"
[ -f "$SAFE" ] && _tier="保守(有safe文件)"
_ps="关闭省电"
[ -f "$PSON" ] && _ps="保留省电(有ps_on文件)"
echo "    resetprop : ${RP:-未找到}"
echo "    备份      : $BASE ($_bs)"
echo "    触控档位  : $_tier"
echo "    网络档位  : $_ps"
echo
echo "[2] 触控挂载:"
find_src
if [ -n "$SRC" ]; then
    if is_mounted "$SRC"; then
        echo "    [OK] $SRC 已 bind 挂载"
    else
        echo "    [FAIL] 未挂载"
    fi
else
    echo "    [FAIL] 原厂 XML 未找到"
fi
echo
echo "[3] XML 关键项 (原厂 -> 当前):"
for pair in game_mode:1 vsync_test_support:1 hsync_test_support:1 frame_insert_support:1 refresh_report_sync_support:1 smooth-level:2 report_rate:2 temper_send_to_fw_support:1 click_sensitive_support:1; do
    _id=${pair%%:*}; _idx=${pair##*:}
    a=$(getvN "$BASE" "$_id" "$_idx" 2>/dev/null)
    b=$(getvN "$DERIVED" "$_id" "$_idx" 2>/dev/null)
    [ -n "$b" ] && [ "$b" != "$a" ] && st="[OK]  " || st="[----]"
    printf "    %s %-26s %s -> %s\n" "$st" "$_id" "$a" "$b"
done
echo
echo "[4] 属性:"
for k in persist.sys.input.resample ro.input.noresample debug.sf.enable_adpf_cpu_hint debug.hwui.use_hint_manager debug.sf.latch_unsignaled debug.sf.disable_backpressure debug.graphics.game_default_frame_rate.disabled; do
    printf "    %-46s = %s\n" "$k" "$(get_prop "$k")"
done
echo
echo "[5] CPU 运行时节点:"
printf "    cpufreq/boost                     = %s\n" "$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null)"
for p in /sys/devices/system/cpu/cpufreq/policy0/walt /sys/devices/system/cpu/cpufreq/policy6/walt; do
    printf "    %-34s = boost:%s load:%s\n" "$p" "$(cat $p/boost 2>/dev/null)" "$(cat $p/hispeed_load 2>/dev/null)"
done
printf "    sched_child_runs_first            = %s\n" "$(cat /proc/sys/kernel/sched_child_runs_first 2>/dev/null)"
echo
echo "[6] 网络:"
printf "    王者 uid                           = %s\n" "$(game_uid)"
for _chain in OUTPUT POSTROUTING; do
    printf "    DSCP %-11s" "$_chain"
    iptables -t mangle -C "$_chain" -m owner --uid-owner "$(game_uid)" -j DSCP --set-dscp-class EF 2>/dev/null \
        && echo " = [OK] EF 标记中" || echo " = [----] 无规则"
done
if [ -x "$WPA_CLI" ] && [ -S "$WPA_SOCK/wlan0" ] && [ ! -f "$WORK/wpa_blocked" ]; then
    printf "    Wi-Fi 省电 (wlan0)                = %s\n" "$("$WPA_CLI" -p "$WPA_SOCK" -i wlan0 get ps 2>/dev/null)"
elif [ -f "$WORK/wpa_blocked" ]; then
    echo "    Wi-Fi 省电 (wlan0)                = 本 ROM ctrl 门禁, 已跳过(wpa_blocked)"
else
    echo "    Wi-Fi 省电 (wlan0)                = 无法查询(wpa_cli/socket缺失)"
fi
printf "    驱动 ini gRuntimePM (persist)      = %s\n" "$(grep '^gRuntimePM' /mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini 2>/dev/null | head -1)"
printf "    ini 原厂备份                       = %s\n" "$([ -s /data/adb/op15_lowlat/ini_WCNSS_qcom_cfg.ini_original.cfg ] && echo 有 || echo 无)"
printf "    Wi-Fi PCIe runtime PM              = %s/%s\n" \
    "$(cat /sys/bus/pci/devices/0000:01:00.0/power/control 2>/dev/null)" \
    "$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)"
printf "    拥塞控制                           = %s\n" "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
printf "    队列策略                           = %s\n" "$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
echo
echo "[7] 日志尾部:"
tail -n 15 "$LOG" 2>/dev/null || echo "    无日志"
