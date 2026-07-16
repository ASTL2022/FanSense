# FanSense — 数据来源速查表 (DATA_SOURCES)

> 记录每类监控数据的来源 API、关键字段及已知限制。
> 新增数据类型时先查本文件，避免重复踩坑。
> 最后更新：2026-06-28

---

## 一、功耗

### 1.1 整机功耗

| 字段 | 说明 |
|------|------|
| **API** | SMC（`SMCKit` / 直接 `IOServiceOpen`）|
| **键名** | `PSTR`（System Total Rail）|
| **单位** | W |
| **刷新频率** | ~1s |
| **放电** | 可用 |
| **充电** | 可用 |
| **注意** | 不要用 `PDTR`——放电时恒为 0；满电 AC 供电时可选读 `PDTR` 做对比 |

### 1.2 适配器输入功耗

| 字段 | 说明 |
|------|------|
| **API** | SMC |
| **键名** | `PDTR`（DC In Total Rail）|
| **单位** | W |
| **注意** | 放电时无适配器 → 恒为 0，仅充电/满电时有效 |

### 1.3 CPU / GPU 分项功耗

> **结论**：GPU 功耗可用 IOReport 读取；CPU 分项功耗在当前 macOS 版本不更新。整机功耗仍用 SMC `PSTR`。

#### 方案对比（2026-06-28 实测）

| 方案 | GPU 功耗 | CPU 功耗 | 备注 |
|------|----------|----------|------|
| **SMC** (`PCPU`/`PGPU`) | ❌ 恒为 0 | ❌ 恒为 0 | Apple Silicon 不通过 SMC 暴露 |
| **IOHIDEventSystem**（iFan 方案）| ❌ 0 个传感器 | ❌ 0 个传感器 | M1 Pro 无 Power 类型 HID 传感器 |
| **IOReport Energy Model** | ✅ `GPU Energy`（nJ）| ❌ 计数器不更新 | 162 个通道，仅 GPU Energy 可用 |
| **powermetrics** | macOS 26 beta `cpu_power=0` | macOS 26 beta `cpu_power=0` | beta bug，等正式版 |

#### IOReport 调用流程（已在 C 层验证）

```c
// 1. 订阅 Energy Model 通道组
CFDictionaryRef em = IOReportCopyChannelsInGroup(
    CFSTR("Energy Model"), NULL, 0, 0, 0);
CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(NULL, 0, em);
CFMutableDictionaryRef subbed = NULL;
void* sub = IOReportCreateSubscription(NULL, desired, &subbed, 0, NULL);

// 2. 两次采样 + 差值
CFDictionaryRef s1 = IOReportCreateSamples(sub, subbed, NULL);
// ... 等待 dt 秒 ...
CFDictionaryRef s2 = IOReportCreateSamples(sub, subbed, NULL);
CFDictionaryRef delta = IOReportCreateSamplesDelta(s1, s2, NULL);

// 3. 遍历 delta 通道，读取能量差值
CFArrayRef channels = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
for (int i = 0; i < CFArrayGetCount(channels); i++) {
    void* ch = (void*)CFArrayGetValueAtIndex(channels, i);
    int64_t val = IOReportSimpleGetIntegerValue(ch, 0);
    if (val == 0) continue;
    CFStringRef name = IOReportChannelGetChannelName(ch);   // e.g. "GPU Energy"
    CFStringRef unit = IOReportChannelGetUnitLabel(ch);     // "nJ"
    // watts = val / dt / scale  (scale: 1e3 mJ, 1e6 uJ, 1e9 nJ)
}
```

#### 已验证的可读通道

| 通道名 | 单位 | 状态 | 实测空闲功耗 |
|--------|------|------|-------------|
| `GPU Energy` | nJ | ✅ 更新正常 | ~0.4–0.8 W |
| `CPU Energy` | mJ | ❌ 计数器不变 | — |
| 所有 `EACC_*` / `PACC_*` / `*DTL*` | mJ | ❌ 计数器不变 | — |
| `ANE0` / `DRAM0` / `ISP0` / `DCS0` | mJ | ❌ 计数器不变 | — |
| `PCIe Port * Energy` | uJ | ⚠️ offset 24 更新（非 SimpleGetIntegerValue）| — |

> **CPU 替代方案**：`CPU ≈ PSTR整机 − GPU`（利用 SMC PSTR 减去 IOReport GPU Energy 做近似估算）。

#### 集成到 fanhelper

IOReport 调用链路已确定，需要：
1. `fanhelper.c` 新增 `power` / `power_start` / `power_stop` 子命令
2. 启动时创建 IOReport 订阅，持续在后台采样
3. Swift 端每秒读一次 delta + 计算瓦数
4. 或在 `fanhelper.c` 内直接做采样循环，输出文本行

**库依赖**：`libIOReport.dylib`（通过 `dlopen`/`dlsym` 动态加载，无需链接）。

---

### 1.4 屏幕功耗（不可用，见 PITFALLS §14）

> 2026-06-28 实测结论：M1 Pro + macOS 26 beta 上**无任何 API 能读到实时屏幕功耗**。

| 尝试方案 | 结果 |
|----------|------|
| IOReport `backlight report`（`MicroAmps value` 等 7 通道）| 返回静态快照值，亮度变化后不复新 |
| IORegistry `AppleCLCD2`（`IOMFBBrightnessLevel` 等）| 同上，亮度变化后属性不变 |
| `DisplayServicesGetBrightness` | ✅ 能读写实时亮度 0–1，但无法获取瓦数 |
| IOReport Energy Model `DCS0` | 计数器不更新（同 CPU 通道）|
| DCP Power 子组 | 仅有占空比/休眠计数，无功率值 |

背光功率理论上 = MicroAmps × 电压，但 MicroAmps 是静态快照值，电压需硬编码机型。唯一可用的实时数据是 `DisplayServicesGetBrightness`（亮度百分比），无法换算瓦数。

> **决定**：放弃屏幕功耗卡片。保留数据源文档供后续参考。

---

### 1.5 GPU 占用率（Device Utilization %）

| 字段 | 说明 |
|------|------|
| **API** | IORegistry `AGXAcceleratorG13X` → `PerformanceStatistics` → `Device Utilization %` |
| **单位** | %（0–100） |
| **刷新频率** | ~1s |
| **权限** | 无需 root |

```swift
// IORegistry 直接读，无需 helper
let svc = IOServiceGetMatchingService(...)  // AGXAcceleratorG13X
IORegistryEntryCreateCFProperties(svc, &props, ...)
let ps = props["PerformanceStatistics"] as? [String: Any]
let gpuUtil = (ps["Device Utilization %"] as? Int) ?? 0  // 0–100
```

另有 `Renderer Utilization %` 和 `Tiler Utilization %` 分项指标，当前仅用总体 `Device Utilization %`。

---

## 二、温度

| 传感器 | SMC 键 | 说明 |
|--------|--------|------|
| CPU | `TC0x` 系列（TC0P / TC0D / TC0E 等，机型而异）| 取可用键中最高值或平均值 |
| GPU | `Tg0D`（Apple Silicon GPU die 温度）| |
| 电池 | `TB0T`–`TB2T`（Battery Temperature 0–2）| 通常取 TB0T |

**API**：SMC 直接读，`SMCKit` 或原始 `IOServiceOpen`。
**单位**：°C（SMC 返回 float）。
**刷新频率**：~1s。

---

## 三、CPU 占用率

| 字段 | 说明 |
|------|------|
| **API** | Mach `host_processor_info(HOST_PROCESSOR_INFO, ...)` |
| **方式** | 读取每个核心的 user / system / idle tick，前后两次差值计算占用率 |
| **刷新频率** | ~1s |
| **注意** | 需要两次采样做差，第一次无法出结果 |

```swift
var cpuInfo: processor_info_array_t?
var numCpuInfo: mach_msg_type_number_t = 0
var numCpus: natural_t = 0
host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                    &numCpus, &cpuInfo, &numCpuInfo)
// 差值计算 (user+system) / (user+system+idle)
```

---

## 四、内存

| 字段 | 说明 |
|------|------|
| **API** | Mach `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` |
| **返回结构** | `vm_statistics64_data_t`：`free_count / active_count / inactive_count / wire_count` |
| **已用内存** | `(active + inactive + wire) × PAGE_SIZE` |
| **总内存** | `sysctl hw.memsize` |
| **刷新频率** | ~1s |

---

## 五、网络速率

| 字段 | 说明 |
|------|------|
| **API** | POSIX `getifaddrs` |
| **方式** | 遍历所有接口，累加 `ifi_ibytes`（下载）/ `ifi_obytes`（上传），前后两次差值 ÷ 间隔 = 速率 |
| **过滤** | 排除 `lo0` 回环接口，只统计 `AF_LINK` 地址族 |
| **单位** | B/s（显示时转换为 KB/s 或 MB/s）|
| **刷新频率** | ~1s |

---

## 六、磁盘使用量

| 字段 | 说明 |
|------|------|
| **API** | POSIX `statvfs("/")`（或用户指定路径）|
| **已用** | `(f_blocks - f_bavail) × f_frsize` |
| **可用** | `f_bavail × f_frsize` |
| **总量** | `f_blocks × f_frsize` |
| **刷新频率** | 低频即可（~5s），变化慢 |

---

## 七、电池信息

### 7.1 基础信息（百分比 / 充放电状态 / 功耗）

| 字段 | 来源 |
|------|------|
| 电量百分比 | `IOPowerSources` → `kIOPSCurrentCapacityKey / kIOPSMaxCapacityKey` |
| 充放电状态 | `IOPowerSources` → `kIOPSPowerSourceStateKey`（"AC Power" / "Battery Power"）|
| 是否正在充电 | `IOPowerSources` → `kIOPSIsChargingKey` |
| 当前功耗（W） | SMC `PSTR`（见 §1.1）|

**注意**：不要用 `B0AC` / `B0PS` 判断充放电状态——B0AC 噪声极大，B0PS bit 定义因机型而异（见 PITFALLS §6、§7）。

### 7.2 续航时间（macOS 26 beta 特殊处理）

| 字段 | 正常 API | macOS 26 beta 替代 |
|------|----------|--------------------|
| 剩余续航 | `IOPowerSources` → `kIOPSTimeToEmptyKey` | IORegistry `AppleSmartBattery` → `TimeRemaining`（分钟）|
| 充满时间 | `IOPowerSources` → `kIOPSTimeToFullChargeKey` | IORegistry `AppleSmartBattery` → `AvgTimeToFull`（分钟）|

**根因**：macOS 26 beta 中 `kIOPSTimeToEmptyKey` 固定返回 -1（beta bug，见 PITFALLS §11）。

**IORegistry 读取示例**：
```swift
let service = IOServiceGetMatchingService(kIOMainPortDefault,
    IOServiceMatching("AppleSmartBattery"))
var props: Unmanaged<CFMutableDictionary>?
IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
let dict = props!.takeRetainedValue() as! [String: Any]
let timeRemaining = dict["TimeRemaining"] as? Int  // 分钟
let avgTimeToFull = dict["AvgTimeToFull"] as? Int  // 分钟
```

---

## 八、风扇转速

| 字段 | 说明 |
|------|------|
| **API** | SMC |
| **读取键** | `F0Ac`（当前转速），`F0Mn`（最低转速），`F0Mx`（最高转速）|
| **设置键** | `F0Tg`（目标转速，需要 root / SMC 写权限）|
| **单位** | RPM |
| **刷新频率** | ~1s |
| **注意** | 写 SMC 需要 `IOServiceOpen` 并有相应权限，FanSense 通过辅助进程或 helper 实现 |
