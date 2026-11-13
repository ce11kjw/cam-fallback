#!/system/bin/sh
# CamFallback - 开机后守护 & WebUI
# 注意：busybox httpd 在 APatch 的 busybox 里没编译 CGI，
#      所以用 nc -lk -e 自建轻量 HTTP 服务（已实测可用）
MODDIR=${0%/*}
LOG=/data/local/tmp/camfb.log
WDIR=/data/local/tmp/camfb-web
PORT=8089

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

# ---- 找工具 ----
RESETPROP=""
for p in /data/adb/ap/bin/resetprop /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop; do
    [ -x "$p" ] && RESETPROP="$p" && break
done
BB=""
for b in /data/adb/ap/bin/busybox /data/adb/ksu/bin/busybox /data/adb/magisk/busybox; do
    [ -x "$b" ] && BB="$b" && break
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)

log "=== service.sh 启动 (busybox=$BB resetprop=$RESETPROP) ==="

reapply() {
    [ -n "$RESETPROP" ] && $RESETPROP ro.boot.camera.config 0 2>>"$LOG"
    setprop vendor.debug.camera.logicalcam.enable_map 1
}

# ---- 等 HAL 首次探测（最多 60 秒）----
i=0
while [ $i -lt 30 ]; do
    P=$(getprop persist.vendor.camera.sensor.probe)
    [ -n "$P" ] && break
    sleep 2; i=$((i+1))
done
log "probe=[$(getprop persist.vendor.camera.sensor.probe)]"

# ---- 抢救：HAL 在崩就重设配置并重启 ----
SVC=$(getprop init.svc.camerahalserver)
if [ "$SVC" = "restarting" ]; then
    log "HAL 崩溃循环 -> 重新应用配置"
    reapply
    setprop ctl.restart camerahalserver
    sleep 10
    log "修复后 svc=$(getprop init.svc.camerahalserver)"
fi

# ============ WebUI（nc 版）============
mkdir -p "$WDIR"
cp -f "$MODDIR/webroot/index.html" "$WDIR/index.html" 2>/dev/null

# HTTP handler：读请求 → 按路径返回
cat > "$WDIR/handler.sh" <<'EOH'
#!/system/bin/sh
# CamFallback HTTP handler
read -r REQ
read -r _H
# 丢弃剩余 header
while read -r H; do
  case "$H" in
    ""|"$(printf '\r')") break ;;
  esac
done

URL=$(echo "$REQ" | awk '{print $2}')
BODY=""
CT="application/json"

case "$URL" in
  /status*)
    P=$(getprop persist.vendor.camera.sensor.probe)
    SVC=$(getprop init.svc.camerahalserver)
    DEV=$(timeout 5 dumpsys media.camera 2>/dev/null | grep -oE 'Number of camera devices: [0-9]+' | grep -oE '[0-9]+$')
    [ -z "$DEV" ] && DEV=0
    CRASH=$(logcat -b crash -d 2>/dev/null | grep -c 'Fatal signal')
    INFO=$(getprop persist.vendor.camera.mi.module.info)
    EXT=$(getprop persist.vendor.camera.mi.module.infoext)
    MAP=$(getprop vendor.debug.camera.logicalcam.enable_map)
    CFG=$(getprop ro.boot.camera.config)
    SEL=$(getenforce)
    MODEL=$(getprop ro.product.odm.marketname)
    [ -z "$MODEL" ] && MODEL=$(getprop ro.product.model)
    VER=$(grep '^version=' /data/adb/modules/cam_fallback/module.prop 2>/dev/null | cut -d= -f2)
    BODY=$(printf '{"probe":"%s","hal":"%s","devices":%s,"crash":%s,"info":"%s","infoext":"%s","enable_map":"%s","camera_config":"%s","selinux":"%s","model":"%s","version":"%s"}' \
      "$P" "$SVC" "$DEV" "$CRASH" "$INFO" "$EXT" "$MAP" "$CFG" "$SEL" "$MODEL" "$VER")
    ;;
  /cmd*)
    DO=$(echo "$URL" | sed -n 's/.*do=\([a-z]*\).*/\1/p')
    RP=""
    for p in /data/adb/ap/bin/resetprop /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop; do
        [ -x "$p" ] && RP="$p" && break
    done
    case "$DO" in
      restart)
        [ -n "$RP" ] && $RP ro.boot.camera.config 0
        setprop vendor.debug.camera.logicalcam.enable_map 1
        setprop ctl.restart camerahalserver
        BODY='{"ok":true,"action":"restart"}'
        ;;
      opencam)
        monkey -p com.android.camera -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        BODY='{"ok":true,"action":"opencam"}'
        ;;
      *)
        BODY='{"ok":false,"msg":"unknown"}'
        ;;
    esac
    ;;
  *)
    CT="text/html; charset=utf-8"
    if [ -f /data/local/tmp/camfb-web/index.html ]; then
      BODY=$(cat /data/local/tmp/camfb-web/index.html)
    else
      BODY="<h1>CamFallback</h1><p>index.html missing</p>"
    fi
    ;;
esac

printf 'HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n%s' \
  "$CT" "${#BODY}" "$BODY"
EOH
chmod 755 "$WDIR/handler.sh"

# 停旧实例
[ -f /data/local/tmp/camfb-web.pid ] && kill -9 "$(cat /data/local/tmp/camfb-web.pid)" 2>/dev/null
if [ -n "$BB" ]; then
    for p in $($BB ps -o pid,args 2>/dev/null | grep "nc -lk -p $PORT" | grep -v grep | awk '{print $1}'); do
        kill -9 "$p" 2>/dev/null
    done
fi
sleep 1

# 启动 nc 服务器
if [ -n "$BB" ] && [ -x "$BB" ]; then
    nohup $BB nc -lk -p $PORT -e "$WDIR/handler.sh" >/dev/null 2>&1 &
    echo $! > /data/local/tmp/camfb-web.pid
    sleep 1
    if $BB netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        log "WebUI 已启动: http://127.0.0.1:$PORT/"
    else
        log "!! WebUI 启动失败（端口 $PORT）"
    fi
else
    log "!! busybox 不可用，WebUI 未启动"
fi

# ---- 巡检：HAL 掉了就修 ----
n=0
while true; do
    sleep 300
    n=$((n+1))
    SVC=$(getprop init.svc.camerahalserver)
    if [ "$SVC" != "running" ]; then
        log "巡检#$n: HAL=$SVC -> 修复"
        reapply
        setprop ctl.restart camerahalserver
    fi
    # WebUI 挂了也拉起来
    if [ -n "$BB" ] && ! $BB netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        log "巡检#$n: WebUI 掉线 -> 重启"
        nohup $BB nc -lk -p $PORT -e "$WDIR/handler.sh" >/dev/null 2>&1 &
        echo $! > /data/local/tmp/camfb-web.pid
    fi
done
