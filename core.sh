#!/system/bin/sh
# ════════════════════════════════════════════════════════════════
#  一加15·王者低延迟引擎 core —— 全层共用的函数库
#
#  层1 触控: /odm/firmware/tp/infiniti/vnd_custom_config_main.xml
#            bind 挂载补丁（基线已按本机 PLK110 出厂原版逐项核对）
#  层2 属性: 输入重采样 / SF / HWUI / 游戏帧率上限
#  层3 CPU : WALT boost + cpufreq boost + 输入升频 + 子进程先跑
#  层4 网络: Wi-Fi 省电关闭（静态 wpa_cli）+ 王者 DSCP EF 标记
#
#  OPL_NO_AUTORUN=1 时只加载函数、不自动执行
#  存在 $SAFE 则触控退回保守档（跳过满速上报/关温度/click）
#  存在 $PSON 则跳过 Wi-Fi 省电关闭
# ════════════════════════════════════════════════════════════════

MODDIR=${MODDIR:-/data/adb/modules/op15_lowlat}

WORK=/data/adb/op15_lowlat
LOG=$WORK/op15_lowlat.log
BASE=$WORK/base_original.xml
DERIVED=$WORK/derived.xml
SAFE=$WORK/safe
PSON=$WORK/ps_on

CAND="/odm/firmware/tp/infiniti/vnd_custom_config_main.xml
/system/odm/firmware/tp/infiniti/vnd_custom_config_main.xml"

GAME_PKG=com.tencent.tmgp.sgame
WPA_SOCK=/data/vendor/wifi/wpa/sockets
WPA_CLI=$MODDIR/bin/wpa_cli

mkdir -p "$WORK" 2>/dev/null

log() { printf '[%s] %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }

# ── resetprop 定位（KSU 在 /data/adb/ksu/bin，不在 PATH） ──
RP=""
find_resetprop() {
    RP=""
    for p in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop \
             /data/adb/magisk/resetprop /sbin/resetprop; do
        [ -x "$p" ] && RP="$p" && break
    done
    [ -n "$RP" ] || RP=$(command -v resetprop 2>/dev/null)
    [ -n "$RP" ] && [ -x "$RP" ] || RP=""
    [ -n "$RP" ]
}

# ── 属性读写：绝不用 setprop（早期引导死锁），resetprop -n 不触发 prop service ──
get_prop() { [ -n "$RP" ] && "$RP" "$1" 2>/dev/null; }

set_prop() {
    _k="$1"; _v="$2"
    [ -n "$RP" ] || return 127
    [ "$(get_prop "$_k")" = "$_v" ] && return 0
    "$RP" -n "$_k" "$_v" >/dev/null 2>&1
    log "PROP $_k <- $_v"
}

is_mounted() { awk -v t="$1" '$2 == t {found=1} END{exit !found}' /proc/mounts 2>/dev/null; }

find_src() {
    SRC=""
    for p in $CAND; do [ -f "$p" ] && { SRC="$p"; return 0; }; done
    return 1
}

# ── 改第 idx 个 <value>（一个 modules 块内从 1 数起） ──
setvN() {
    _id="$1"; _idx="$2"; _nv="$3"
    awk -v id="$_id" -v idx="$_idx" -v nv="$_nv" '
    {
        if ($0 ~ /<modules id="/) {
            s = $0; sub(/.*<modules id="/, "", s); sub(/".*/, "", s)
            inm = (s == id); if (inm) cnt = 0
        }
        if (inm && !done && match($0, /<value>[^<]*<\/value>/)) {
            cnt++
            if (cnt == idx) { sub(/<value>[^<]*<\/value>/, "<value>" nv "</value>"); done = 1 }
        }
        print
    }' "$DERIVED" > "$DERIVED.tmp" 2>/dev/null

    if [ -s "$DERIVED.tmp" ]; then
        mv -f "$DERIVED.tmp" "$DERIVED"
        log "XML  $_id[$_idx] <- $_nv"
    else
        log "ERROR: awk 处理 $_id 输出为空, 本次跳过"
        rm -f "$DERIVED.tmp"
    fi
}

getvN() {
    awk -v id="$2" -v idx="$3" '
    {
        if ($0 ~ /<modules id="/) {
            s = $0; sub(/.*<modules id="/, "", s); sub(/".*/, "", s)
            inm = (s == id); if (inm) cnt = 0
        }
        if (inm && match($0, /<value>[^<]*<\/value>/)) {
            cnt++
            if (cnt == idx) {
                t = substr($0, RSTART, RLENGTH)
                sub(/<value>/, "", t); sub(/<\/value>/, "", t)
                print t; exit
            }
        }
    }' "$1" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════
#  层1：触控固件采样/同步表（bind 挂载，绝不改原厂文件本身）
# ════════════════════════════════════════════════════════════════
apply_touch() {
    find_src || { log "ERROR: 原厂 XML 未找到, 已试: $CAND"; return 1; }
    log "src=$SRC"

    # 先卸掉该文件上已有的 bind（自己上一轮挂的），保证读到真原厂
    if is_mounted "$SRC"; then
        umount "$SRC" 2>/dev/null && log "umount 旧挂载: $SRC"
    fi

    # 首次备份原厂原文，之后永远保留
    if [ ! -s "$BASE" ]; then
        cp -f "$SRC" "$BASE" 2>/dev/null
        log "备份原厂 -> $BASE ($(wc -l < "$BASE" 2>/dev/null) 行)"
    fi
    [ -s "$BASE" ] || { log "ERROR: 原厂备份失败, 放弃本次挂载"; return 1; }

    cp -f "$BASE" "$DERIVED" 2>/dev/null

    # ── 基础层（全局生效，副作用小） ──
    setvN game_mode                    1 1          # 面板游戏模式常开（本机出厂 0）
    setvN vsync_test_support           1 0          # 不等垂直同步（本机出厂已 0，保持）
    setvN hsync_test_support           1 0          # 不等水平同步（本机出厂已 0，保持）
    setvN frame_insert_support         1 0          # 关补帧插值（出厂 1 -> 0）
    setvN refresh_report_sync_support  1 "60,120"   # 同步节拍去掉 144/165（出厂 60,120,144,165）
    setvN smooth-level                 2 "0,0,0,0,0,0" # 关平滑滤波（出厂 16,25,23,21,18,16）

    # ── 极限层（默认开；存在 SAFE 文件则退回保守） ──
    if [ -f "$SAFE" ]; then
        log "保守档: 跳过 report_rate / 温度上报 / click 灵敏度"
    else
        setvN report_rate               2 "1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
        setvN temper_send_to_fw_support 1 0
        setvN click_sensitive_support   1 1
        log "极限档: report_rate 满速上报 + 关温度上报 + click 灵敏度"
    fi

    # ── 挂载前自检：行数必须与原厂一致，且关键项确实改到 ──
    _l1=$(wc -l < "$DERIVED" 2>/dev/null); _l0=$(wc -l < "$BASE" 2>/dev/null)
    [ "$_l1" = "$_l0" ] || { log "ERROR: 派生文件行数异常 ($_l0->$_l1), 放弃挂载"; return 1; }

    _b=$(getvN "$DERIVED" game_mode 1)
    [ "$_b" = "1" ] || { log "ERROR: game_mode 补丁未生效, 放弃挂载(布局可能不同)"; return 1; }

    mount --bind "$DERIVED" "$SRC" 2>/dev/null
    if is_mounted "$SRC"; then
        log "bind OK -> $SRC"
        return 0
    else
        log "ERROR: bind 失败 (可能 SELinux 拒绝), 原厂文件未被覆盖"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  层2：属性（输入重采样 / SF / HWUI / 游戏帧率限制）
# ════════════════════════════════════════════════════════════════
apply_props() {
    set_prop persist.sys.input.resample   0   # 本机 ROM 的输入重采样开关（出厂 1）
    set_prop ro.input.noresample          1   # 通用开关（部分 ROM 读它）
    set_prop debug.sf.enable_adpf_cpu_hint true
    set_prop debug.hwui.use_hint_manager   true
    set_prop debug.sf.latch_unsignaled     1
    set_prop debug.graphics.game_default_frame_rate.disabled 1
    if [ ! -f "$SAFE" ]; then
        set_prop debug.sf.disable_backpressure 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  层3：运行时节点（WALT 升频 / cpufreq boost，全带值比对守卫）
# ════════════════════════════════════════════════════════════════
apply_cpu() {
    # cpufreq boost（本机：/sys/devices/system/cpu/cpufreq/boost 与 policy*/boost）
    for f in /sys/devices/system/cpu/cpufreq/boost \
             /sys/devices/system/cpu/cpufreq/policy*/boost; do
        [ -f "$f" ] && [ -w "$f" ] || continue
        cur=$(cat "$f" 2>/dev/null)
        [ "$cur" = "1" ] || { echo 1 > "$f" 2>/dev/null && log "SYSFS $f <- 1 (原 $cur)"; }
    done

    # WALT 调度器：boost 常开 + 更早进入高频档（本机默认 boost=0, hispeed_load=90）
    for p in /sys/devices/system/cpu/cpufreq/policy*/walt; do
        [ -d "$p" ] || continue
        for f in "$p/boost" "$p/hispeed_load"; do
            [ -f "$f" ] && [ -w "$f" ] || continue
            case "$f" in
                *boost) want=1 ;;
                *)       want=80 ;;
            esac
            cur=$(cat "$f" 2>/dev/null)
            [ "$cur" = "$want" ] || { echo "$want" > "$f" 2>/dev/null && log "SYSFS $f <- $want (原 $cur)"; }
        done
    done

    # 新进程先跑（输入处理线程更快被调度）
    f=/proc/sys/kernel/sched_child_runs_first
    if [ -f "$f" ] && [ -w "$f" ]; then
        cur=$(cat "$f" 2>/dev/null)
        [ "$cur" = "1" ] || { echo 1 > "$f" 2>/dev/null && log "SYSFS $f <- 1 (原 $cur)"; }
    fi

    # 高通/OPPO cpu_boost 输入加速（本机无此节点则自动跳过）
    for f in \
        /sys/module/cpu_boost/parameters/input_boost_enable \
        /sys/module/cpu_boost/parameters/input_boost_enabled \
        /sys/module/oplus_cpu_boost/parameters/input_boost_enable \
        /sys/module/oplus_cpu_boost/parameters/touch_boost; do
        [ -f "$f" ] && [ -w "$f" ] || continue
        cur=$(cat "$f" 2>/dev/null)
        [ "$cur" = "1" ] || { echo 1 > "$f" 2>/dev/null && log "SYSFS $f <- 1 (原 $cur)"; }
    done
}

# ════════════════════════════════════════════════════════════════
#  层4b：Wi-Fi 驱动 ini 补丁（gRuntimePM 2 -> 0）
#  生效文件是内核驱动经 ueventd 固件加载器读取的 persist 配置：
#    /mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini
#  （dmesg 实测；/vendor/etc/wifi 下只是工厂默认回退，驱动不读）
#  该分区可写、且这份文件本身就是厂商留给用户覆盖的配置，
#  所以用【原地直写】而非 bind 挂载：保持原 inode 与 SELinux 标签，
#  避免 ueventd 因标签不符被 SELinux 拒绝（bind 方案实测会翻车）。
#  原文件永远备份在 $WORK；卸载/ini_safe 时自动还原。
# ════════════════════════════════════════════════════════════════
INI_TARGETS="/mnt/vendor/persist/wlan/WCNSS_qcom_cfg.ini"

apply_ini() {
    # 运行时放 ini_safe 标记即跳过（不用重装），并还原原厂
    if [ -f "$WORK/ini_safe" ]; then
        _base=$WORK/ini_WCNSS_qcom_cfg.ini_original.cfg
        _t=$INI_TARGETS
        if [ -s "$_base" ] && ! cmp -s "$_base" "$_t" 2>/dev/null; then
            cat "$_base" > "$_t" 2>/dev/null \
                && log "ini_safe: 已还原原厂 ini" \
                || log "ini_safe: 还原失败"
        fi
        return 0
    fi

    _t=$INI_TARGETS
    [ -f "$_t" ] || { log "INI: 目标不存在 $_t, 跳过"; return 1; }

    _base=$WORK/ini_WCNSS_qcom_cfg.ini_original.cfg
    [ -s "$_base" ] || cp -f "$_t" "$_base" 2>/dev/null
    [ -s "$_base" ] || { log "INI: 备份失败, 跳过"; return 1; }

    # 已是 0 就跳过（幂等）
    grep -q '^gRuntimePM=0' "$_t" && { log "INI: 已是 gRuntimePM=0"; return 0; }

    # 生成到 /data 临时文件，再原地写回（保持 inode/标签/权限不变）
    awk '{ sub(/^gRuntimePM=.*/, "gRuntimePM=0"); print }' "$_t" > "$WORK/ini_new.tmp" 2>/dev/null
    grep -q '^gRuntimePM=0' "$WORK/ini_new.tmp" || { rm -f "$WORK/ini_new.tmp"; log "INI: 生成失败, 跳过"; return 1; }

    cat "$WORK/ini_new.tmp" > "$_t" 2>/dev/null
    if grep -q '^gRuntimePM=0' "$_t"; then
        log "INI: gRuntimePM -> 0 (persist 原地直写, 原厂已备份)"
        rm -f "$WORK/ini_new.tmp"
        return 0
    else
        log "ERROR: INI 写入失败, 未生效"
        rm -f "$WORK/ini_new.tmp"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════
#  层4c：网络
#  4c-1 Wi-Fi 省电关闭（wpa_cli 直连 wpa_supplicant 控制 socket）
#        本机 NetworkEnhancer 写的通用节点在高通 WCN 驱动上不存在，
#        它那套在这台机器上是空转 —— 这里是本模块真正补上的缺口。
#  4c-2 王者荣耀 DSCP EF 标记：路由器/电竞网络若认 DSCP 会优先转发
# ════════════════════════════════════════════════════════════════
wpa_ps_off() {
    if [ ! -f "$WPA_CLI" ]; then
        log "WARN: $WPA_CLI 缺失, 跳过省电关闭"
        return 1
    fi
    # KSU 解压可能丢掉可执行位，运行时自愈
    chmod 755 "$WPA_CLI" 2>/dev/null
    # 上一轮已确认本 ROM 的 ctrl 门禁不放行（Android 17 wpa_supplicant 域限制），
    # 不再反复空等；删掉该标记重启可重试
    [ -f "$WORK/wpa_blocked" ] && { log "WPA 门禁已确认, 跳过(删 $WORK/wpa_blocked 可重试)"; return 1; }
    _ok=0; _tried=0; _rc=0
    for _if in wlan0 wlan1; do
        [ -S "$WPA_SOCK/$_if" ] || continue
        _tried=1
        _out=$("$WPA_CLI" -p "$WPA_SOCK" -i "$_if" set ps 0 2>&1)
        case "$_out" in
            OK|*"OK"*)
                log "WPA $_if ps <- 0"
                _ok=1 ;;
            *"timed out"*)
                log "WARN: WPA $_if 无响应(Android 17 ctrl 门禁)"
                _rc=1 ;;
            *)
                log "WARN: WPA $_if ps 设置失败: $_out"
                _rc=1 ;;
        esac
    done
    [ "$_tried" = "1" ] && [ "$_ok" = "0" ] && touch "$WORK/wpa_blocked" 2>/dev/null
    return $_rc
}

game_uid() {
    GAME_UID=$(stat -c %u "/data/user/0/$GAME_PKG" 2>/dev/null)
    case "$GAME_UID" in
        ""|*[!0-9]*) GAME_UID="" ;;
    esac
    [ -n "$GAME_UID" ] && [ "$GAME_UID" -ge 10000 ] || GAME_UID=""
    printf '%s' "$GAME_UID"
}

ens_dscp() {
    _u=$(game_uid)
    [ -n "$_u" ] || return 0
    for _chain in OUTPUT POSTROUTING; do
        iptables -t mangle -C "$_chain" -m owner --uid-owner "$_u" \
            -j DSCP --set-dscp-class EF 2>/dev/null && continue
        iptables -t mangle -I "$_chain" 1 -m owner --uid-owner "$_u" \
            -j DSCP --set-dscp-class EF 2>/dev/null \
            && log "DSCP $_chain uid=$_u <- EF" \
            || log "WARN: DSCP $_chain 写入失败"
    done
}

apply_net() {
    # ini 补丁每次进网络层都核对一遍（挂载丢了就重挂）
    apply_ini
    # 省电关闭默认开；放 $PSON 文件则跳过
    if [ -f "$PSON" ]; then
        log "PS_ON 标记存在, 跳过 Wi-Fi 省电关闭"
    else
        wpa_ps_off
    fi
    ens_dscp
}

# ════════════════════════════════════════════════════════════════
#  看门狗：系统把挂载/节点/规则改回去时兜底（30 秒一轮）
# ════════════════════════════════════════════════════════════════
watchdog() {
    find_src
    if [ -n "$SRC" ] && ! is_mounted "$SRC"; then
        log "WATCHDOG: 挂载丢失, 重挂"
        apply_touch
    fi
    _ini_need=0
    for _t in $INI_TARGETS; do
        grep -q '^gRuntimePM=0' "$_t" 2>/dev/null || _ini_need=1
    done
    [ "$_ini_need" = "1" ] && apply_ini
    apply_cpu
    ens_dscp
    _n=$((_n+1))
    if [ $((_n % 10)) -eq 0 ]; then
        apply_props
        if [ ! -f "$PSON" ]; then wpa_ps_off; fi
    fi
}

if [ "$OPL_NO_AUTORUN" = "1" ]; then
    log "OPL_NO_AUTORUN=1, 只加载函数"
else
    find_resetprop || log "WARN: 未找到 resetprop, 层2 属性不会写入"
    apply_props
    apply_touch
    apply_cpu
    apply_net
fi
