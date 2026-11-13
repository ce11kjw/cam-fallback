#!/system/bin/sh
# CamFallback - 开机后守护 + 可选 WebUI（http 端口服务）
#
# 说明：
#   KSU / APatch 管理器的「模块 WebUI」直接托管 webroot/index.html，
#   页面通过 window.ksu.exec 执行命令取数据，**不需要任何端口**。
#
#   这里的 nc 服务只是给「用浏览器直接访问」留的入口（可选）。
#   端口用高位 38946，避开常见的 8080/8089/9090 等冲突。

MODDIR=${0%/*}
LOG=/data/local/tmp/camfb.log
WDIR=/data/local/tmp/camfb-web
PORT=38946          # 高位端口，避免冲突

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done

# ---- 找工具 ----
RESETPROP=""
for p in /data/adb/ap/bin/resetprop /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /system/bin/resetprop; do
    [ -x "$p" ] && RESETPROP="$p" && break
done
BB=""
for b in /data/adb/ap/bin/busybox /data/adb/ksu/bin/busybox /data/adb/magisk/busybox; do
    [ -x "$b" ] && BB="$b" && break
done
[ -z "$BB" ] && BB=$(command -v busybox 2>/dev/null)

log "=== service.sh 启动 (busybox=$BB resetprop=$RESETPROP port=$PORT) ==="

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

# ============ 可选：浏览器用 HTTP 入口 ============
mkdir -p "$WDIR"
cp -f "$MODDIR/webroot/index.html" "$WDIR/index.html" 2>/dev/null

cat > "$WDIR/handler.sh" <<'EOH'
#!/system/bin/sh
read -r REQ
read -r _H
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
    BODY=$(printf '{"probe":"%s","hal":"%s","devices":%s,"crash":%s,"info":"%s","infoext":"%s","enable_map":"%s","camera_config":"%s","selinux":"%s"}' \
      "$P" "$SVC" "$DEV" "$CRASH" "$INFO" "$EXT" "$MAP" "$CFG" "$SEL")
    ;;
  *)
    CT="text/html; charset=utf-8"
    if [ -f "$WDIR/index.html" ]; then
      BODY=$(cat "$WDIR/index.html")
    else
      BODY="<h1>CamFallback</h1><p>index.html missing</p>"
    fi
    ;;
esac

printf 'HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n%s' \
  "$CT" "${#BODY}" "$BODY"
EOH
chmod 755 "$WDIR/handler.sh"

# 清理旧实例（含旧端口 8089 的残留）
[ -f /data/local/tmp/camfb-web.pid ] && kill -9 "$(cat /data/local/tmp/camfb-web.pid)" 2>/dev/null
if [ -n "$BB" ]; then
    for p in $($BB ps -o pid,args 2>/dev/null | grep -E "nc -lk -p (8089|$PORT)" | grep -v grep | awk '{print $1}'); do
        kill -9 "$p" 2>/dev/null
    done
fi
sleep 1

if [ -n "$BB" ] && [ -x "$BB" ]; then
    nohup $BB nc -lk -p $PORT -e "$WDIR/handler.sh" >/dev/null 2>&1 &
    echo $! > /data/local/tmp/camfb-web.pid
    sleep 1
    if $BB netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        log "HTTP 入口: http://127.0.0.1:$PORT/"
    else
        log "!! HTTP 入口启动失败（端口 $PORT 被占？）"
    fi
fi

# ---- 巡检 ----
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
    if [ -n "$BB" ] && ! $BB netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        log "巡检#$n: HTTP 入口掉线 -> 重启"
        nohup $BB nc -lk -p $PORT -e "$WDIR/handler.sh" >/dev/null 2>&1 &
        echo $! > /data/local/tmp/camfb-web.pid
    fi
done
