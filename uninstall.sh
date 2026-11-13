#!/system/bin/sh
# CamFallback - 卸载时还原原始属性

LOG=/data/local/tmp/camfb.log
echo "[$(date '+%m-%d %H:%M:%S')] === uninstall ===" >> "$LOG"

RESETPROP=""
for p in /data/adb/ap/bin/resetprop /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop; do
    [ -x "$p" ] && RESETPROP="$p" && break
done

# 停 WebUI
[ -f /data/local/tmp/camfb-web.pid ] && kill "$(cat /data/local/tmp/camfb-web.pid)" 2>/dev/null
rm -rf /data/local/tmp/camfb-web /data/local/tmp/camfb-web.pid

# 还原属性
ORIG=/data/adb/camfallback/orig.conf
if [ -f "$ORIG" ]; then
    . "$ORIG"
    [ -n "$ORIG_INFO" ] && setprop persist.vendor.camera.mi.module.info "$ORIG_INFO"
    [ -n "$ORIG_INFOEXT" ] && setprop persist.vendor.camera.mi.module.infoext "$ORIG_INFOEXT"
    [ -n "$ORIG_MAP" ] && setprop vendor.debug.camera.logicalcam.enable_map "$ORIG_MAP"
    if [ -n "$RESETPROP" ] && [ -n "$ORIG_CAMCFG" ]; then
        $RESETPROP ro.boot.camera.config "$ORIG_CAMCFG" 2>/dev/null
    fi
    echo "已还原: info=[$ORIG_INFO] ext=[$ORIG_INFOEXT]" >> "$LOG"
fi

# 重启相机服务让它回到原始行为
setprop ctl.restart camerahalserver 2>/dev/null

rm -rf /data/adb/camfallback
echo "卸载完成，属性已还原" >> "$LOG"
