# Changelog

本文件记录 CamFallback 的所有版本变更。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

---

## [v1.0.1] - 2026-11-14

### 修复

- **WebUI 在 Root 管理器里显示「HTTP 404」**
   - 原因：页面由 KSU/APatch 管理器内置服务托管，`fetch('status')` 这类
     相对路径请求会打到**管理器自己的端口**（不是模块端口），必然 404。
   - 修复：改用管理器标准桥 `window.ksu.exec(command, options, callbackName)`，
     回调式取值（兼容 Promise 实现 + 20s 超时兜底）。
     现在**完全不依赖端口**，点开就能用。

- **HTTP 入口端口从 8089 改为 38946**
   - 8089 在多模块环境下容易撞车，改用高位端口。
   - 该入口仅用于「浏览器直接访问」，管理器 WebUI 不需要它。

### 改进

- 一次 `exec` 采集全部状态（原来的多次请求合并为 1 次）
- 桥探测兼容 `window.ksu` / `window.KernelSU` / `window.apatch` /
  `window.magisk` / `window.mm`
- 读取失败时在顶部显示具体错误，而不是整页空白

---

## [v1.0.0] - 2026-11-14

首个正式版本。基于 Redmi K60 Ultra（MT6985）超广角传感器损坏的真实故障排查。

### 新增

- **自动检测失效 sensor**
  读取 `persist.vendor.camera.sensor.probe`，逐颗判断（5 次采样），
  含任一 `S` 视为可用，全 `F` 视为失效。

- **HAL 设备表剔除**
  从 `persist.vendor.camera.mi.module.info` / `infoext` 中移除失效镜头，
  避免 `HalLogicalDeviceList::createDeviceMap()` 空指针崩溃。

- **三项捆绑配置**
  | 项目 | 值 |
  |---|---|
  | `mi.module.info` | 移除失效镜头 |
  | `vendor.debug.camera.logicalcam.enable_map` | `1`（易失，开机重设）|
  | `ro.boot.camera.config` | `0`（需 `resetprop`）|

  实测三项缺一不可：只改前两项会导致 `getSensorId()` 断言失败
  （`KeyedVector: key not found`）。

- **post-fs-data 早期注入**
  在 `camerahalserver` 启动前完成配置，避免首次启动即崩溃。

- **service.sh 抢救机制**
   - 等 HAL 首次探测完成后复核（最多 60 秒）
   - 发现 `init.svc.camerahalserver=restarting` 时自动重设配置并重启
   - 每 5 分钟巡检一次，HAL 异常时自愈

- **WebUI 面板**
   - 实时摄像头数 / HAL 状态
   - 每颗 sensor 的探测位图（`S`/`F`）
   - 当前生效的全部配置项（含 `camera.config` 是否为 0 的校验）
   - 一键「重启相机服务」「打开相机」
   - 自动刷新，纯原生 JS，无外部依赖

- **模块 action 按钮**
  命令行输出 sensor 探测详情、HAL 状态、生效配置、最近日志。

- **安装/卸载脚本**
   - `customize.sh`：MTK 平台检查、原属性备份、失效 sensor 提示
   - `uninstall.sh`：停止 WebUI、还原原始属性、重启相机服务

### 修复的问题

- 摄像头全部无法打开（`Number of camera devices: 0`）
- `camerahalserver` 每 5 秒 SIGSEGV 崩溃循环
- 崩溃导致的 CPU 高负载（实测 `load average: 21+` → 正常）
- 相机不可用期间 App 白屏/闪退

### 已验证

| 机型 | SoC | Android | 状态 |
|---|---|---|---|
| Redmi K60 Ultra (`corot`) | MT6985 天玑 9200+ | 16 (API 36) | ✅ |

**实测数据**（超广角 IMX355 损坏）：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 摄像头数 | 0 | **2** |
| HAL | `restarting` | `running` |
| 崩溃/小时 | 720+ | **0** |
| 主摄 IMX800 | ❌ | ✅ |
| 前摄 IMX596 | ❌ | ✅ |

### 已知限制

- 硬件损坏的摄像头无法通过软件修复
- `enable_map` 为易失属性，每次开机都需重设
- 依赖小米/MTK 私有属性 `persist.vendor.camera.mi.module.info`
- 仅支持 MTK 平台（高通等平台 HAL 架构不同）

---

## 版本号规则

`v主.次.修订`

- **主**：架构变更（如改用不同的注入方式）
- **次**：新增功能（如支持更多 sensor 类型、新增 WebUI 功能）
- **修订**：bug 修复、兼容性调整
