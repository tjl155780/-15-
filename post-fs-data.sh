#!/system/bin/sh
MODDIR=${0%/*}
[ -f "$MODDIR/core.sh" ] || exit 0
# core.sh 未设 OPL_NO_AUTORUN，source 时自动应用全部四层
. "$MODDIR/core.sh"
