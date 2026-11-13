#!/system/bin/sh
# CamFallback - 模块按钮动作
MODDIR=${0%/*}
LOG=/data/local/tmp/camfb.log

echo "════════ CamFallback 状态 ════════"
echo "模块版本 : $(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)"
echo
echo "── Sensor 探测 ──"
P=$(getprop persist.vendor.camera.sensor.probe)
echo "probe    : ${P:-<等待HAL探测>}"
for s in front main ultra macro tele; do
    V=$(echo "$P" | sed -n "s/.*<$s:\([SF]*\)>.*/\1/p")
    [ -z "$V" ] && continue
    if echo "$V" | grep -q 'S'; then
        echo "  $s : ✓ 可用 ($V)"
    else
        echo "  $s : ✗ 失效 ($V)  ← 已从 HAL 剔除"
    fi
done
echo
echo "── HAL 状态 ──"
echo "服务      : $(getprop init.svc.camerahalserver)"
echo "摄像头数  : $(timeout 8 dumpsys media.camera 2>/dev/null | grep -oE 'Number of camera devices: [0-9]+' | grep -oE '[0-9]+$')"
echo "本次崩溃  : $(logcat -b crash -d 2>/dev/null | grep -c 'Fatal signal') 次"
echo
echo "── 生效配置 ──"
echo "module.info      : $(getprop persist.vendor.camera.mi.module.info)"
echo "module.infoext   : $(getprop persist.vendor.camera.mi.module.infoext)"
echo "enable_map       : $(getprop vendor.debug.camera.logicalcam.enable_map)"
echo "ro.boot.camera.config : $(getprop ro.boot.camera.config)  (需为 0)"
echo "SELinux          : $(getenforce)"
echo
echo "── WebUI ──"
echo "http://127.0.0.1:8089/"
echo
echo "── 最近日志 ──"
tail -12 "$LOG" 2>/dev/null
