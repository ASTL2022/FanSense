# FanControl

macOS 菜单栏风扇控制与系统监控工具，支持 Apple Silicon Mac 实时查看温度、功耗、CPU/GPU/内存占用，并手动调节风扇转速。

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-orange)
![Swift](https://img.shields.io/badge/swift-5.9+-red)

---

## 功能特性

### 🔥 实时监控
- **温度监测**：CPU / GPU / 电池三路温度实时显示，支持温度阈值告警
- **功耗追踪**：整机功耗（PSTR）+ GPU 功耗（IOReport）+ 60 秒功耗曲线图
- **电池管理**：电量百分比、剩余续航、充电状态、能效等级评估
- **性能占用**：CPU / GPU / 内存占用率 + 状态评级（正常/较高/过载）
- **网络速率**：实时下载/上传速率（KB/s 或 MB/s）
- **磁盘使用**：根分区已用/可用空间

### 🌀 风扇控制
- **自动温控**：系统默认自动调速模式
- **手动调速**：拖动滑块精确控制风扇转速（1200–4700 RPM）
- **动态图标**：菜单栏图标旋转速度实时反映风扇转速

### 🎨 设计亮点
- **毛玻璃面板**：NSPanel + HUD 材质，亮暗模式自适应
- **双列布局**：560pt 宽度，左侧电池/能效/风扇，右侧温度/占用/网络/磁盘
- **语义色系统**：CPU 紫色、内存蓝色、GPU 绿色、网络青色、磁盘靛蓝，阈值告警自动变橙/红
- **无闪烁刷新**：等宽数字字体 + frame-based 布局，1 秒刷新无抖动

---

## 系统要求

- **操作系统**：macOS 12+ (Monterey 及以上)
- **处理器**：Apple Silicon (M1 / M1 Pro / M1 Max / M2 / M3 系列)
- **权限**：需要 root 权限设置风扇转速（通过 `fanhelper` 辅助进程实现）

> **注意**：Intel Mac 不支持（SMC 键名和 IOReport 通道与 Apple Silicon 不同）。

---

## 安装使用

### 方式一：下载编译好的 DMG（推荐）

1. 下载 `FanControl.dmg`
2. 双击挂载，拖动 `FanControl.app` 到应用程序文件夹
3. 首次运行时，系统会提示输入密码授权 `fanhelper` 辅助工具
4. 菜单栏出现风扇图标，点击打开监控面板

### 方式二：从源码编译

```bash
cd /path/to/fanapp
chmod +x build.sh
./build.sh
```

构建脚本会：
- 编译 Swift 主程序 (`main.swift` + 视图组件)
- 编译 C 辅助工具 `fanhelper`（SMC 读写）
- 生成 app bundle (`FanControl.app`)
- 打包为 DMG 镜像

编译产物：
- `FanControl` - 主可执行文件
- `fanhelper` - SMC 辅助工具
- `FanControl.app` - 应用程序包
- `FanControl.dmg` - 安装镜像

---

## 使用说明

### 基础操作

1. **查看监控数据**：点击菜单栏风扇图标打开面板
2. **手动调速**：拖动风扇卡片的滑块到目标转速，松手后立即生效
3. **恢复自动温控**：点击面板底部「恢复自动温控」按钮
4. **退出应用**：点击面板底部「退出」按钮

### 界面布局

```
┌─────────────────────────────────┐
│      MacBook Pro M1 Pro         │  ← Header（机型 + 运行时间）
│       运行 3 天 4 小时           │
├──────────────┬──────────────────┤
│ 【电池】      │ 【温度】          │
│  86% 放电中   │  CPU 72° 正常    │
│  剩余 3h20m  │  GPU 58° 正常    │
│  曲线图       │  电池 32° 正常   │
├──────────────┼──────────────────┤
│ 【能效】      │ 【占用】          │
│  18.3W 高效   │  CPU 74% 正常    │
│              │  GPU 13% 正常    │
│              │  内存 61% 正常   │
├──────────────┼──────────────────┤
│ 【风扇】      │ 【网络】          │
│  1850 RPM    │  ↓ 120 KB/s      │
│  [滑块]      │  ↑ 45 KB/s       │
│              ├──────────────────┤
│              │ 【磁盘】          │
│              │  已用 512 GB     │
│              │  可用 245 GB     │
└──────────────┴──────────────────┘
│ [恢复自动温控]  [退出]          │
└─────────────────────────────────┘
```

### 告警阈值

| 指标 | 正常 | 警告 | 危险 |
|------|------|------|------|
| CPU 温度 | < 60°C | 60–94°C | ≥ 95°C |
| GPU 温度 | < 60°C | 60–94°C | ≥ 95°C |
| 电池温度 | < 35°C | 35–44°C | ≥ 45°C |
| CPU 占用 | < 70% | 70–89% | ≥ 90% |
| GPU 占用 | < 70% | 70–89% | ≥ 90% |
| 内存占用 | < 60% | 60–89% | ≥ 90% |
| 磁盘占用 | < 80% | 80–89% | ≥ 90% |

---

## 技术架构

### 核心组件

#### 1. Swift 主程序 (`main.swift`)
- **AppController**：应用生命周期管理、定时刷新、面板控制
- **视图组件**：
  - `HeaderView` - 机型与运行时间
  - `BatteryBarView` - 电池状态 + 充电曲线图
  - `ChargeChartView` - 60 秒功耗历史
  - `EfficiencyView` - 能效等级评估
  - `FanSliderView` - 风扇转速滑块
  - `TempBarView` - 三路温度监控
  - `MetricBarView` - CPU/GPU/内存/磁盘通用条形图
  - `NetBarView` - 网络速率

#### 2. C 辅助工具 (`fanhelper.c`)
- **SMC 读写**：通过 `IOKit` 框架的 `IOServiceOpen` 访问 SMC
- **支持命令**：
  - `fan` - 读取当前转速
  - `fan <rpm>` - 设置目标转速
  - `temp <key>` - 读取温度（TC0P / Tg0D / TB0T 等）
  - `power` - 读取整机功耗（PSTR）

#### 3. 数据源层 (`DataSources.swift`)
封装所有系统 API 调用：
- **功耗**：SMC `PSTR` + IOReport `GPU Energy`
- **温度**：SMC `TC0x` / `Tg0D` / `TB0T`
- **CPU 占用**：`host_processor_info` + delta 计算
- **内存**：`host_statistics64` + `sysctl hw.memsize`
- **GPU 占用**：IORegistry `AGXAcceleratorG13X` → `Device Utilization %`
- **网络**：`getifaddrs` + 字节差值 ÷ 时间
- **磁盘**：`statvfs("/")`
- **电池**：`IOPowerSources` + IORegistry `AppleSmartBattery`

### 数据刷新策略

- **快速刷新**（1 秒）：温度、功耗、CPU/GPU/内存占用、网络、风扇转速
- **慢速刷新**（30 秒）：电池状态、续航时间、磁盘使用量

### 权限模型

- **无需 root**：读取温度、功耗、占用率、网络、磁盘
- **需要 root**：写 SMC（设置风扇转速）
  - 通过 `fanhelper` 以 root 身份运行，主程序通过管道通信调用

---

## 文档

- **[DATA_SOURCES.md](DATA_SOURCES.md)** - 所有监控数据的 API 来源、字段定义、已知限制
- **[DESIGN.md](DESIGN.md)** - UI 设计规范、token 系统、组件库、布局规则
- **[PITFALLS.md](PITFALLS.md)** - 开发踩坑记录（SMC 数据源、NSPanel 刷新、IOReport 等）

---

## 常见问题

### Q1: 为什么需要输入密码？
设置风扇转速需要写 SMC，macOS 要求 root 权限。`fanhelper` 会被安装到系统目录（`/Library/PrivilegedHelperTools`），仅在首次运行时要求授权。

### Q2: 手动设置风扇后会自动恢复吗？
不会。手动设置的转速会持续生效，直到点击「恢复自动温控」或重启系统。

### Q3: Intel Mac 能用吗？
不支持。Intel Mac 的 SMC 键名（如 `PCPU` / `PGPU`）和 IOReport 通道与 Apple Silicon 不同，需要单独适配。

### Q4: macOS 26 beta 续航时间显示不准？
macOS 26 beta 存在 bug，`kIOPSTimeToEmptyKey` 固定返回 -1。当前版本已切换到 IORegistry `AppleSmartBattery` → `TimeRemaining` 读取，可正常工作。

### Q5: 为什么 CPU 功耗显示为 0 或近似值？
Apple Silicon 的 IOReport `CPU Energy` 通道在当前 macOS 版本不更新。当前使用 `CPU ≈ PSTR整机 − GPU` 做近似估算。

### Q6: 能否监控外接显示器功耗？
不支持。M1 Pro 上所有实时屏幕功耗 API（IOReport backlight / IORegistry AppleCLCD2）均返回静态快照，无法获取实时瓦数。

---

## 开发路线

### 已完成 ✅
- [x] 菜单栏图标 + NSPanel 实时面板
- [x] 温度/功耗/电池/风扇/CPU/GPU/内存/网络/磁盘监控
- [x] 手动风扇转速控制
- [x] 60 秒功耗历史曲线
- [x] 能效等级评估
- [x] 语义色系统 + 阈值告警
- [x] 动态旋转图标（转速映射）
- [x] DMG 打包与一键构建

### 规划中 🚧
- [ ] 风扇转速曲线自定义（温度 → 转速映射）
- [ ] 历史数据导出（CSV / JSON）
- [ ] 多风扇支持（MacBook Pro 16" 双风扇）
- [ ] 通知中心集成（温度告警推送）
- [ ] 命令行模式（headless 运行 + 日志输出）

---

## 致谢

本项目在开发过程中参考了以下开源项目和技术文档：

- [SMCKit](https://github.com/beltex/SMCKit) - SMC 读写封装
- [iStat Menus](https://bjango.com/mac/istatmenus/) - 系统监控 UI 设计灵感
- Apple IOKit / IOReport 框架文档
- [powermetrics](https://gist.github.com/samlown/5404439) - 功耗监控方案探索

---

## 许可协议

MIT License

---

## 作者

dr.t @ MarsCandyBox

如有问题或建议，欢迎提交 Issue 或 Pull Request。
