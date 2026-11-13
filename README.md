# CamFallback — 相机降级兼容模块

> 一颗摄像头坏了，其他全部用不了？这个模块帮你救回来。

[![Platform](https://img.shields.io/badge/platform-MTK%20mtkcam-22d3ee)]()
[![Root](https://img.shields.io/badge/root-APatch%20%7C%20KernelSU%20%7C%20Magisk-a3e635)]()
[![Android](https://img.shields.io/badge/android-13%2B-22d3ee)]()

---

## 问题：为什么"坏一颗，全都不开"

这是 MTK 平台 `mtkcam` HAL 的一个**设计缺陷**（不是你的手机坏了）。

Android 相机启动流程：

```
camerahalserver 启动
  └─ CameraDeviceManagerBase::initialize()
      └─ enumerateDevicesLocked()
          └─ HalLogicalDeviceList::createDeviceMap()   ← ★ 在这里遍历所有 sensor
              └─ HalSensorList::searchSensors()         ← 探测每颗 sensor 是否在线
```

`createDeviceMap()` 会**假定所有声明的 sensor 都存在**。当某颗探测失败时：

| 缺失的镜头 | HAL 行为 |
|---|---|
| 前置（front） | ✅ 有 `DEFAULT_VIRTUAL_DEVICE_IDS_MAP_FRONT_LOST` 兜底，能跳过 |
| 微距（macro） | ✅ 有 `DEFAULT_VIRTUAL_DEVICE_IDS_MAP_MACRO_LOST` 兜底，能跳过 |
| **超广角（ultra）** | ❌ **没有兜底表** → 空指针解引用 → SIGSEGV |
| **主摄（main）** | ❌ **没有兜底表** → 空指针解引用 → SIGSEGV |

崩溃现场（`/data/tombstones/tombstone_*`）：

```
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x1
Cause: null pointer dereference

backtrace:
  #00 pc 0x50f70  libmtkcam.logicalmodule.so
       (NSCam::HalLogicalDeviceList::createDeviceMap()+5808)
  #01 pc 0x554c0  libmtkcam.logicalmodule.so (searchDevices()+288)
  #02 pc 0xd260   libmtkcam_devicemgr.so (onEnumerateDevicesLocked()+368)
  #03 pc 0x1ad30  libmtkcam_devicemgr.so (enumerateDevicesLocked()+80)
  #04 pc 0x1a00   libmtkcam_devicemgr.so (initialize()+976)
  ...
  #12 pc 0x38bc   camerahalserver (main+684)
```

因为是 **HAL 初始化阶段**崩溃，`init` 会每 5 秒重启一次服务：

```
init: Service 'camerahalserver' received signal 11
init: process with updatable components 'camerahalserver' exited 4 times in 4 minutes
init: starting service 'camerahalserver'...
```

结果：`camerahalserver` 永远起不来 → `cameraserver` 拿不到任何设备：

```
$ dumpsys media.camera
Number of camera devices: 0     ← 全部摄像头消失
```

**结论：主摄再完好也没用，因为整个 HAL 进程根本没活下来。**

---

## 解决方案

核心思路：**在 HAL 枚举前，把已损坏的 sensor 从设备表里剔除**，让它只看到完好的镜头。

需要同时满足三个条件（缺一不可，实测验证）：

| # | 项目 | 值 | 作用 |
|---|---|---|---|
| 1 | `persist.vendor.camera.mi.module.info` | 移除失效镜头 | 决定 HAL 声明哪些后摄 |
| 2 | `vendor.debug.camera.logicalcam.enable_map` | `1` | 启用逻辑设备 ID 映射（**易失**，开机必须重设）|
| 3 | `ro.boot.camera.config` | `0` | 改为 0 才走兼容分支；为 `1` 时 `getSensorId()` 会 abort |

> ⚠️ 第 3 项是关键：`ro.boot.camera.config=1` 时，即使隐藏了 ultra，
> HAL 仍会在 `TemplateRequest::onCreate → getSensorId()` 处
> `KeyedVector: key not found` 断言失败。

模块在 `post-fs-data.sh` 阶段（**早于 camerahalserver 启动**）完成上述三项设置。

---

## 效果

Redmi K60 Ultra（超广角 IMX355 损坏）实测：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 摄像头数量 | **0** | **2** |
| HAL 状态 | `restarting`（每 5s 崩溃） | `running` ✅ |
| 崩溃次数/小时 | 720+ | **0** |
| 主摄（IMX800） | ❌ 不可用 | ✅ 正常 |
| 前摄（IMX596） | ❌ 不可用 | ✅ 正常 |
| 超广角（IMX355） | ❌ 损坏 | ❌ 损坏（硬件问题，无法修复）|

CPU 负载也从 `load average: 21+` 恢复正常（不再有崩溃循环）。

---

## 安装

### 要求

- **MTK 平台**（`ro.board.platform` 以 `mt` 开头）
- Android 13+
- Root：**APatch / KernelSU / Magisk** 任一（需要 `resetprop`）
- 已有一颗或多颗摄像头传感器失效

### 步骤

1. 从 [Releases](../../releases) 下载 `CamFallback-vX.Y.Z.zip`
2. 在 Root 管理器里安装（APatch：模块 → 安装；Magisk：从本地安装）
3. **重启手机**
4. 开机后打开相机验证

也可以装完直接点模块的**「执行」按钮**查看状态，或访问 WebUI：

```
http://127.0.0.1:8089/
```

---

## WebUI

模块自带一个本地网页面板（端口 `8089`，仅回环），由 `service.sh` 开机启动。

**功能：**

- 📊 实时摄像头数量和 HAL 状态
- 🔍 每颗 sensor 的探测结果（`S`=通过 / `F`=失败，5 次采样）
- ⚙️ 显示当前生效的全部配置项
- 🔄 一键「重启相机服务」（自动重设配置）
- 📷 一键「打开相机」

**访问方式：**

- 手机浏览器直接开 `http://127.0.0.1:8089/`
- 或用 SSH/ADB 端口转发到电脑：
  ```bash
  adb forward tcp:8089 tcp:8089
  # 然后电脑上开 http://127.0.0.1:8089/
  ```

> WebUI 使用 busybox `httpd` + CGI，**无外部依赖**，离线可用。
> 只监听 `127.0.0.1`，局域网/公网访问不到。

---

## 自动检测逻辑

模块**不是硬编码**只修某一台机器，而是每次开机自动判断：

```
读取 persist.vendor.camera.sensor.probe
  格式：<front:SSSSS><main:SSSSS><ultra:FFFFF><macro:FFFFF>
  每个位置是一颗 sensor，S=探测成功，F=失败

逐颗判断：
  含任一 S → 视为「可用」→ 保留在 module.info 里
  全为 F   → 视为「失效」→ 从 module.info 里剔除
```

**为什么含 `S` 就算活？**
某些接触不良的模组会间歇性探测成功（实测出现过 `SSSFF`）。
这种情况下它仍可能工作，保留更安全。

**兜底保护：**
- 如果全部后摄都失效 → 不修改配置（改了只会更糟）
- 如果 `probe` 为空（还没探测过）→ 等 `service.sh` 补处理

---

## 兼容性

| 项目 | 支持情况 |
|---|---|
| MTK SoC | ✅ 理论通用（基于 mtkcam 架构，非机型专属） |
| 高通/其他平台 | ❌ 无效（不同 HAL，问题机制也不同） |
| APatch | ✅ 实测通过 |
| KernelSU | ✅ 理论支持（找 `ksu/bin/resetprop`） |
| Magisk | ✅ 理论支持（找 `magisk/resetprop`） |
| Android 13-16 | ✅ 实测 Android 16 |

**已验证机型：**

- Redmi K60 Ultra（`corot` / MT6985 天玑 9200+ / Android 16）

其他 MTK 机型欢迎反馈。理论上只要满足"mtkcam + 有 sensor 失效"就能用。

---

## 已知限制

1. **坏的摄像头修不好** —— 这是硬件故障，模块只是让其他摄像头能用
2. **每次开机都要重设** —— `enable_map` 是易失属性，`ro.boot.camera.config` 来自 bootloader
3. **重度依赖 `persist.vendor.camera.mi.module.info`** —— 这是小米/MTK 私有属性，
   纯 AOSP 或其他 OEM 的 MTK 机器可能不存在
4. **超广角相关功能会缺失** —— 相机 App 里可能仍有"超广角"按钮但点击无效

---

## 排查

### 看日志

```bash
tail -f /data/local/tmp/camfb.log
```

### 手动检查状态

```bash
# sensor 探测结果
getprop persist.vendor.camera.sensor.probe

# HAL 是否活着
getprop init.svc.camerahalserver

# 设备数
dumpsys media.camera | grep "Number of camera"

# 三个关键配置
getprop persist.vendor.camera.mi.module.info
getprop vendor.debug.camera.logicalcam.enable_map
getprop ro.boot.camera.config     # 必须是 0
```

### 常见问题

**Q: 装完重启，摄像头数还是 0？**

逐一检查三个配置项。最常见的是 `ro.boot.camera.config` 没改成 0 —— 说明 `resetprop` 路径没找到。手动验证：

```bash
su -c 'resetprop ro.boot.camera.config 0'
su -c 'getprop ro.boot.camera.config'   # 应输出 0
```

**Q: HAL 还是每 5 秒崩？**

```bash
# 看崩溃点
logcat -b crash -d | grep -E "Abort message|createDeviceMap|getSensorId"

# 确认坏 sensor 真的被隐藏了
getprop persist.vendor.camera.mi.module.info
# 应该看不到失效的那个（如 back_ultra=imx355 应消失或为 none）
```

**Q: 主摄能用，但画质/对焦异常？**

模块只解决"能不能打开"，不改变 ISP 调优。若主摄本身也有隐患（我们的 `probe` 里 visible 但有 `F`），可能影响体验。

**Q: 想临时关掉模块？**

```bash
su -c 'touch /data/adb/modules/cam_fallback/disable'
# 重启后失效
```

---

## 卸载

在 Root 管理器里移除模块，或：

```bash
su -c 'rm -rf /data/adb/modules/cam_fallback'
```

`uninstall.sh` 会自动：
- 停止 WebUI
- **还原原始属性**（从 `/data/adb/camfallback/orig.conf` 读取安装时备份）
- 重启相机服务

> ⚠️ 如果原始状态就是崩溃的（因为硬件确实坏了），卸载后相机会回到打不开的状态。
> 这是预期行为 —— 说明硬件问题仍在。

---

## 原理补充：为什么 `ro.boot.camera.config` 这么关键

这个属性来自 bootloader，正常值 `1`。改成 `0` 后，mtkcam 走的是
"非标准/兼容"分支，在构建 `TemplateRequest` 时不再强制校验每个
logical device 都有对应的 sensor id。

实测对照（隐藏 ultra 后）：

| `camera.config` | 结果 |
|---|---|
| `1` | `createDeviceMap()` 能过，但 `TemplateRequest::onCreate → getSensorId()` **abort**（`KeyedVector key not found`），设备数 0 |
| `0` | 枚举成功 2 个设备，**零崩溃**，HAL 稳定运行 |

所以三项配置是**捆绑生效**的，不能少任何一项。

---

## 参考

- MTK mtkcam HAL3 架构：`vendor/mediatek/proprietary/hardware/mtkcam-core/`
- 崩溃点源码：`utils/LogicalCam/HalLogicalDeviceList.cpp` — `createDeviceMap()`
- 缺失兜底表：`VirtualDeviceIdsMapHelper.cpp` — `DEFAULT_VIRTUAL_DEVICE_IDS_MAP_*_LOST`
- AOSP Camera HAL3 生命周期：`hardware/libhardware/include/hardware/camera3.h`

---

## License

MIT

## 作者

aplm123

> 本模块源于一次真实的硬件故障排查。如果你的手机也遇到"一颗摄像头坏了导致全部打不开"，
> 希望它能帮上忙。欢迎提 Issue 反馈机型适配情况。
