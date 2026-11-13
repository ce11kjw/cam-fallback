#!/system/bin/sh
# CamFallback - 安装脚本
SKIPUNZIP=0

ui_print " "
ui_print "════════════════════════════════"
ui_print "  CamFallback 相机降级兼容"
ui_print "════════════════════════════════"
ui_print " "

# 架构检查
ARCH=$(getprop ro.product.cpu.abi)
ui_print "- 设备 : $(getprop ro.product.odm.marketname)"
ui_print "- 型号 : $(getprop ro.product.model) ($(getprop ro.product.device))"
ui_print "- SoC  : $(getprop ro.board.platform)"
ui_print "- 系统 : Android $(getprop ro.build.version.release) / $(getprop ro.build.version.incremental)"
ui_print " "

# 只支持 MTK（本方案针对 MTK mtkcam 的 HAL 崩溃逻辑）
SOC=$(getprop ro.board.platform)
case "$SOC" in
  mt*)
    ui_print "- MTK 平台检查 : 通过 ($SOC)"
    ;;
  *)
    ui_print "! 警告：当前平台 ($SOC) 不是 MTK"
    ui_print "! 本模块只对 MTK mtkcam HAL 的崩溃问题有效"
    ui_print "! 其他平台安装不会有作用，且可能干扰相机"
    ui_print " "
    ui_print "! 3 秒后继续安装（如不需要请立即音量键退出）"
    sleep 3
    ;;
esac

# 检查 sensor 探测状态
PROBE=$(getprop persist.vendor.camera.sensor.probe)
ui_print "- 当前 sensor 探测:"
ui_print "    ${PROBE:-<无数据，重启后生效>}"

DEAD=""
echo "$PROBE" | grep -oE '<(front|main|ultra|macro|tele):[SF]+>' | while read -r item; do
    NAME=$(echo "$item" | sed 's/<\([a-z]*\):.*/\1/')
    BITS=$(echo "$item" | sed 's/.*:\([SF]*\)>/\1/')
    echo "$BITS" | grep -q 'S' || echo "  ✗ $NAME 探测失败 ($BITS)"
done
ui_print " "

# 备份原始属性（卸载时可还原）
mkdir -p /data/adb/camfallback
if [ ! -f /data/adb/camfallback/orig.conf ]; then
    cat > /data/adb/camfallback/orig.conf <<EOF
ORIG_INFO=$(getprop persist.vendor.camera.mi.module.info)
ORIG_INFOEXT=$(getprop persist.vendor.camera.mi.module.infoext)
ORIG_MAP=$(getprop vendor.debug.camera.logicalcam.enable_map)
ORIG_CAMCFG=$(getprop ro.boot.camera.config)
EOF
    ui_print "- 已备份原始属性到 orig.conf"
fi

mkdir -p /data/adb/camfallback
ui_print "- 配置目录: /data/adb/camfallback"
ui_print " "

# 权限
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/action.sh 0 0 0755
set_perm_recursive $MODPATH/webroot 0 0 0755 0644

ui_print "────────────────────────────────"
ui_print " 安装完成"
ui_print "────────────────────────────────"
ui_print " "
ui_print "下次开机自动生效。"
ui_print " "
ui_print "立即生效方法："
ui_print "  1. 直接重启手机（推荐）"
ui_print "  2. 或打开 WebUI 点「重启相机服务」"
ui_print " "
ui_print "WebUI: http://127.0.0.1:8089/"
ui_print "  （开机后由 service.sh 启动）"
ui_print " "
ui_print "模块按钮可查看 sensor 探测详情。"
ui_print " "
