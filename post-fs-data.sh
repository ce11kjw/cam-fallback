#!/system/bin/sh
# CamFallback - 开机早期注入（必须在 camerahalserver 启动前）
MODDIR=${0%/*}
LOG=/data/local/tmp/camfb.log

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

RESETPROP=""
for p in /data/adb/ap/bin/resetprop /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /system/bin/resetprop; do
    [ -x "$p" ] && RESETPROP="$p" && break
done

log "=== post-fs-data 启动, resetprop=$RESETPROP ==="

# ---- 1. 读取 sensor 探测结果，找出坏掉的镜头 ----
# 格式: <front:SSSSS><main:SSSSS><ultra:FFFFF><macro:FFFFF>
# S=成功 F=失败
PROBE=$(getprop persist.vendor.camera.sensor.probe)
log "sensor.probe = [$PROBE]"

if [ -z "$PROBE" ]; then
    log "probe 为空，等 HAL 首次探测后再判断（service.sh 会补处理）"
fi

# 判断某颗是否"全失败"（FFFFF 或全 F 且长度>=3）
is_dead() {
    local val=$(echo "$PROBE" | sed -n "s/.*<$1:\([SF]*\)>.*/\1/p")
    [ -z "$val" ] && return 1
    # 全 F 才算死；含任一 S 视为可用（间歇性可探测到的也算活）
    echo "$val" | grep -q 'S' && return 1 || return 0
}

# ---- 2. 生成 mi.module.info（只声明活着的后摄）----
# 原值: back_main=imx800;back_ultra=imx355;
BACK_MAIN_MODEL=""
if [ -f /data/adb/camfallback/models.conf ]; then
    . /data/adb/camfallback/models.conf
else
    # 从当前属性反推型号
    CUR=$(getprop persist.vendor.camera.mi.module.info)
    BACK_MAIN_MODEL=$(echo "$CUR" | sed -n 's/.*back_main=\([^;]*\).*/\1/p')
    BACK_ULTRA_MODEL=$(echo "$CUR" | sed -n 's/.*back_ultra=\([^;]*\).*/\1/p')
    FRONT_MAIN_MODEL=$(echo "$CUR" | sed -n 's/.*front_main=\([^;]*\).*/\1/p')
    [ -z "$FRONT_MAIN_MODEL" ] && FRONT_MAIN_MODEL=$(getprop persist.vendor.camera.mi.module.infoext | sed -n 's/.*front_main=\([^;]*\).*/\1/p')
fi

NEW_INFO=""
NEW_EXT=""

# 主摄
if is_dead main; then
    log "main: 探测失败 -> 剔除"
else
    [ -n "$BACK_MAIN_MODEL" ] && [ "$BACK_MAIN_MODEL" != "none" ] && NEW_INFO="${NEW_INFO}back_main=${BACK_MAIN_MODEL};"
fi

# 超广角（缺失兜底表里没有 ULTRA_LOST，所以必须主动剔除）
if is_dead ultra; then
    log "ultra: 探测失败 -> 剔除（这是崩溃主因）"
else
    [ -n "$BACK_ULTRA_MODEL" ] && [ "$BACK_ULTRA_MODEL" != "none" ] && NEW_INFO="${NEW_INFO}back_ultra=${BACK_ULTRA_MODEL};"
fi

# 前摄
if is_dead front; then
    log "front: 探测失败 -> 剔除"
else
    [ -n "$FRONT_MAIN_MODEL" ] && [ "$FRONT_MAIN_MODEL" != "none" ] && NEW_EXT="${NEW_EXT}front_main=${FRONT_MAIN_MODEL};"
fi

# macro / tele 一般不存在，保持 none
NEW_EXT="${NEW_EXT}back_macro=none;"

# 兜底：一个都不剩就别动，否则更糟
if [ -z "$NEW_INFO" ]; then
    log "!! 后摄全部失效，保留原配置不动"
    NEW_INFO=$(getprop persist.vendor.camera.mi.module.info)
fi
if [ -z "$NEW_EXT" ] || [ "$NEW_EXT" = "back_macro=none;" ]; then
    log "!! 前摄失效，保留原配置"
    NEW_EXT=$(getprop persist.vendor.camera.mi.module.infoext)
fi

log "将设置 info=[$NEW_INFO] ext=[$NEW_EXT]"
setprop persist.vendor.camera.mi.module.info "$NEW_INFO"
setprop persist.vendor.camera.mi.module.infoext "$NEW_EXT"

# ---- 3. 关键：ro.boot.camera.config 必须为 0 ----
if [ -n "$RESETPROP" ]; then
    $RESETPROP ro.boot.camera.config 0 2>>"$LOG"
    log "ro.boot.camera.config -> [$($RESETPROP ro.boot.camera.config 2>/dev/null)]"
else
    log "!! 找不到 resetprop，无法改 ro.boot.camera.config"
fi

# ---- 4. 启用逻辑设备 ID 映射 ----
setprop vendor.debug.camera.logicalcam.enable_map 1
log "enable_map -> [$(getprop vendor.debug.camera.logicalcam.enable_map)]"

log "=== post-fs-data 完成 ==="
