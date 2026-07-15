# FanSense

macOS 菜单栏风扇控制与系统监控工具，支持 Apple Silicon Mac。实时查看温度、功耗、CPU/GPU/内存占用，可手动调节风扇转速。

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-orange)
![Swift](https://img.shields.io/badge/swift-5.9+-red)

---

## 功能

### 监控
- **温度**：CPU / GPU / 电池三路温度，阈值变色告警
- **功耗**：整机功耗（SMC PSTR）+ GPU 功耗（IOReport），60 秒实时曲线
- **电池**：电量、剩余续航、充电状态、能效等级
- **占用**：CPU / GPU / 内存占用率 + 状态评级
- **网络**：实时下载/上传速率
- **磁盘**：根分区使用量 + SSD 健康度（NVMe SMART 磨损值）

### 风扇控制
- **自动模式**：系统默认温控
- **手动模式**：滑块设定转速，拉到最左恢复系统自动温控
- **历史曲线**：60 秒转速曲线，按模式分色（蓝 = 自动，橙 = 手动）
- **菜单栏图标**：风扇实际转动时图标旋转；CPU/GPU ≥ 80°C 时变为火焰

### 界面
- 原生 `NSPanel` 玻璃材质，亮暗模式自适应
- 双列布局，等宽数字，1 秒刷新无抖动
- 右键菜单栏图标退出

---

## 系统要求

- **操作系统**：macOS 15+（玻璃面板效果需 macOS 26+）
- **处理器**：Apple Silicon
- **权限**：首次需 root 安装 `fanhelper`（风扇转速写入走 SMC）

> Intel Mac 不支持（SMC 键名和 IOReport 通道不同）。

---

## 安装

从源码编译：

```bash
git clone https://github.com/ASTL2022/FanSense.git
cd FanSense
chmod +x build.sh
./build.sh
```

构建脚本会编译 Swift 主程序和 C 辅助工具，并打包为 `FanControl.app`。

安装辅助工具（仅首次）：

```bash
sudo cp fanhelper /usr/local/bin/fanhelper
sudo chown root:wheel /usr/local/bin/fanhelper
sudo chmod u+s /usr/local/bin/fanhelper
```

---

## 使用

1. 点击菜单栏风扇图标打开面板
2. 拖动滑块到目标转速，短暂防抖后生效
3. 滑块拉到最左即恢复系统自动温控
4. 右键菜单栏图标 → 退出（退出时自动交还系统温控）

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
| SSD 健康 | ≥ 90% | 70–89% | < 70% |

---

## 技术架构

**Swift 主程序**（`main.swift` + 视图组件）
- `AppController` — 生命周期、定时刷新、面板管理
- 视图：`BatteryBarView`、`ChargeChartView`、`EfficiencyView`、`FanView`、`TempBarView`、`MetricBarView`、`NetBarView`

**C 辅助工具**（`fanhelper.c`、`smc.c`、`nvme_smart.c`）
- SMC 读写：IOKit
- NVMe SMART：`IONVMeSMARTUserClient` 插件接口（仅内置 SSD，无需 root）
- 命令：`read` / `sensors` / `all` / `smart` / `set <rpm>` / `auto`

**数据源层**（`DataSources.swift`）
- **功耗**：SMC `PSTR` + IOReport `GPU Energy`
- **温度**：SMC `TC0x` / `Tg0D` / `TB0T`
- **CPU 占用**：`host_processor_info` + delta 计算
- **内存**：`host_statistics64` + `sysctl hw.memsize`
- **GPU 占用**：IORegistry `AGXAccelerator` → Device Utilization %
- **网络**：`getifaddrs` + 字节差值 ÷ 时间
- **磁盘**：`volumeAvailableCapacityForImportantUsage`（与系统设置口径一致）
- **电池**：`IOPowerSources` + IORegistry `AppleSmartBattery`

### 刷新策略

- **快速**（1 秒，面板打开时）：温度、功耗、占用、网络、风扇转速
- **慢速**（30 秒）：电池状态、磁盘使用量
- **面板关闭时**：每 10 秒采样风扇状态（用于图标），每 60 秒采样功耗；SMART 启动时读一次

### 权限模型

- **无需 root**：全部监控（温度、功耗、占用、网络、磁盘、SMART）
- **需要 root**：写 SMC（设置风扇转速），由 setuid 的 `fanhelper` 代理

---

## 文档

- **[DATA_SOURCES.md](DATA_SOURCES.md)** — 所有监控数据的 API 来源、字段定义、已知限制
- **[DESIGN.md](DESIGN.md)** — UI 设计规范、token 系统、组件库、布局规则
- **[PITFALLS.md](PITFALLS.md)** — 开发踩坑记录（SMC 数据源、NSPanel 刷新、IOReport 等）

---

## 常见问题

**为什么需要输入密码？**  
设置风扇转速需要写 SMC，macOS 要求 root 权限。`fanhelper` 以 setuid root 运行；监控本身不需要任何权限。

**手动设置风扇后会自动恢复吗？**  
手动转速持续生效，直到滑块拉回最左、退出应用或重启。应用退出时会自动恢复系统温控。

**Intel Mac 能用吗？**  
不支持。SMC 键名和 IOReport 通道与 Apple Silicon 不同。

**为什么 CPU 功耗是估算值？**  
Apple Silicon 的 IOReport `CPU Energy` 通道在当前 macOS 不更新，用 `CPU ≈ 整机 PSTR − GPU` 近似。

**SSD 健康不显示？**  
SMART 仅支持内置 NVMe 盘，且需要安装最新版 `fanhelper`。

---

## 开发路线

- [ ] 风扇转速曲线自定义（温度 → 转速映射）
- [ ] 历史数据导出（CSV / JSON）
- [ ] 多风扇支持（MacBook Pro 16" 双风扇）
- [ ] 命令行模式

---

## 致谢

- [SMCKit](https://github.com/beltex/SMCKit) — SMC 读写封装
- Apple IOKit / IOReport 框架文档
- [powermetrics](https://gist.github.com/samlown/5404439) — 功耗监控方案探索

---

## 许可协议

Copyright (C) 2026 dr.t @ MarsCandyBox

GPL-3.0-or-later，见 [LICENSE](LICENSE)。分发本软件或其衍生品（包括售卖）必须向每位接收者提供完整源码和本协议。未经许可，不得使用 "FanSense" 名称为衍生产品背书或宣传。

---

## 作者

dr.t @ MarsCandyBox

如有问题或建议，欢迎提交 Issue 或 Pull Request。
