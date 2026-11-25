#!/system/bin/sh
MODDIR=${0%/*}
[ -f "$MODDIR/core.sh" ] || exit 0
export OPL_NO_AUTORUN=1
. "$MODDIR/core.sh"

# 等开机完成后兜底应用一次（vendor touch-aidl / wpa_supplicant 可能晚起）
_i=0
while [ "$_i" -lt 90 ]; do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 2
    _i=$((_i + 1))
done
sleep 12

log "==== service begin (boot 等待轮次=$_i) ===="
find_resetprop || log "WARN: 未找到 resetprop"
apply_props
apply_touch
apply_cpu
apply_net

# 看门狗：30 秒一轮（全带值比对，开销可忽略）；模块被卸载后自动退出
_n=0
while [ -d "$MODDIR" ]; do
    sleep 30
    watchdog
done
log "==== service exit ===="
