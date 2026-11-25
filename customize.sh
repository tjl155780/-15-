#!/system/bin/sh
SKIPUNZIP=0

M=$(getprop ro.product.model 2>/dev/null)
ui_print " "
ui_print "- 设备: ${M:-未知}"
ui_print "- 一加15·王者低延迟引擎 v1.0.0"
ui_print "  按 PLK110 / Android 17 出厂基线定制"
ui_print " "
ui_print "- 触控: 面板游戏模式常开 + 关补帧/平滑滤波/同步节拍"
ui_print "        + 满速上报 + 关温度上报 + click 灵敏度 (极限档默认开)"
ui_print "- 网络: Wi-Fi 省电关闭 (wpa_cli) + 王者荣耀 DSCP EF 优先级"
ui_print "- CPU : WALT boost / cpufreq boost / 输入升频常开"
ui_print " "
ui_print "- 退回保守: su 后 touch /data/adb/op15_lowlat/safe 再重启"
ui_print "- 保留省电: su 后 touch /data/adb/op15_lowlat/ps_on 再重启"
ui_print "- 装完重启生效"
ui_print " "

case "$(getprop ro.product.model 2>/dev/null)" in
    PLK110) : ;;
    *) ui_print "! 警告: 本模块按 PLK110 基线定制, 非此机型请谨慎" ;;
esac

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in post-fs-data.sh service.sh core.sh diag.sh uninstall.sh customize.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
[ -f "$MODPATH/bin/wpa_cli" ] && set_perm "$MODPATH/bin/wpa_cli" 0 0 0755

mkdir -p /data/adb/op15_lowlat 2>/dev/null

# 说明：Wi-Fi 驱动 ini 补丁在 post-fs 阶段 bind 挂载（core.sh 里 apply_ini），
# 本机实测 KSU magic mount 覆盖不了内核驱动读取的 /vendor 文件。
# 运行时放 /data/adb/op15_lowlat/ini_safe 标记可跳过 ini 补丁。
