# FanSense — 踩坑清单 (PITFALLS)

> 仅收录 FanSense（菜单栏风扇/功耗控制工具）相关踩坑。
> 主项目踩坑见 `~/MarsCandyBox/PITFALLS.md`。
> 最后更新：2026-06-27 · 共 12 条

---

## 一、macOS NSPanel 实时刷新

### 1. NSMenu 打开时 runloop 进入模态，display() 全失效
- **现象**：菜单数据每秒刷新，但打开菜单后 UI 冻住，关闭才更新
- **根因**：`NSMenu` 打开时接管 runloop，主线程 `display()` 被挂起
- **教训**：实时刷新的菜单栏 UI 必须用 `NSPanel`（`.borderless + .nonactivatingPanel`），不能用 NSMenu

### 2. NSStackView 不知道 frame-based 自定义 NSView 的高度
- **现象**：切换到 NSPanel 后 UI 挤成一团
- **根因**：NSStackView 用 Auto Layout，不认识手动 frame 的自定义视图尺寸
- **教训**：panel 内用手动 `NSView` container + 逐个设 frame，不要用 NSStackView

---

## 二、SMC 功耗数据源

### 3. 整机功耗用 PSTR，不是 PDTR
- **现象**：放电时整机功耗恒为 0
- **根因**：`PDTR`（DC In Total Rail）是适配器输入，放电时没有适配器 → 恒 0；`PSTR`（System Total Rail）插电/放电两态都实时更新
- **教训**：整机功耗统一读 `PSTR`；满电 AC 供电时可选读 `PDTR`

### 4. InstantAmperage × Voltage 在 macOS 26 beta 更新极慢
- **现象**：放电功耗固定一个值，5–30 秒不变
- **根因**：M1 Pro SMC 的 InstantAmperage 更新频率 10–30s，是硬件设计；powermetrics 在 macOS 26 beta `cpu_power = 0 mW`（beta bug）
- **教训**：macOS 26 beta 不要依赖 powermetrics 或 IOReport；统一用 `PSTR`

### 5. InstantAmperage 是 uint64 存成 int64，Swift `as? Int` 能正确解释
- **现象**：ioreg 看到 `InstantAmperage = 18446744073709550397`，实际是 -1219 mA
- **教训**：不需要特殊处理，Swift `as? Int`（Int64）在 64-bit 系统上按位解释 CFNumber(uint64) 是正确的

### 6. B0AC（SMC 电流）噪声极大，不能用来判断 AC/电池状态
- **现象**：mode 在充电/放电之间乱跳，每隔几秒闪变
- **根因**：B0AC 是硬件级噪声，会在充电过程中随机跳到负值（unsigned int16 溢出）
- **教训**：AC/电池状态判断统一用 `IOPowerSources`（`kIOPSIsChargingKey` / `kIOPSPowerSourceStateKey`），不要读 B0AC / B0PS

### 7. B0PS bit0 在不同 M 系列机型上定义不同
- **现象**：mode 判断全部反转
- **根因**：`B0PS bit0: 0=AC, 1=battery` 在某些机型定义相反
- **教训**：同上，用 IOPowerSources 替代

### 8. 充电瓦数不能用 B0AC × B0AV 计算
- **现象**：充电瓦数显示 0 或跳动严重
- **根因**：B0AC 更新频率极慢（10–30s），乘积无实时意义
- **教训**：充电中整机功耗同样用 `PSTR`，满电时切 `PDTR`

---

## 三、通知权限（macOS SPM 裸 binary）

### 9. 通知不弹 — 裸 binary 无签名
- **现象**：`usernotificationsd` 日志 `Entitlement required to request user notifications`
- **根因**：`swiftc` 直接编译的裸 binary 没有代码签名，系统拒绝通知请求
- **教训**：必须打成 `.app` bundle 并 `codesign --entitlements` 签名后通知才能弹

### 10. UNUserNotificationCenter 调用必须在主线程
- **现象**：通知静默丢失，无报错
- **根因**：`UNUserNotificationCenter.add()` 要求主线程
- **铁律**：所有 UN 调用包 `DispatchQueue.main.async {}`

---

### 11. kIOPSTimeToEmptyKey 在 macOS 26 beta 返回 -1
- **现象**：续航时间一直显示"估算中"
- **根因**：macOS 26 beta 的 `IOPowerSources` `kIOPSTimeToEmptyKey` 固定返回 -1（beta bug）
- **教训**：改读 IORegistry `AppleSmartBattery` 的 `TimeRemaining`（分钟），同理充电时间读 `AvgTimeToFull`

---

## 四、CPU/GPU 分项功耗

### 12. M1 Pro 上 CPU/GPU 分项功耗完全不可读

- **现象**：SMC 读 CPU/GPU 功耗键全部返回 0；IOHIDEventSystem 枚举 177 个传感器，无任何 CPU/GPU/Package 名称
- **根因（SMC）**：Apple Silicon 不通过 SMC 暴露分项功耗，相关键存在但恒为 0
- **根因（IOHIDEventSystem）**：M1 Pro 的 HID 传感器仅有 PMU 电压/电流轨道（ibuck/ildo/vbuck）、温度（tdie/tdev）、陀螺仪、加速度计等；`"CPU Package total"` 是 iFan 的 **UI 层本地化标签**，不是传感器原始名称，Intel Mac 或 ARM 特定型号才有该 HID 通道
- **教训**：M1 Pro 上分项功耗只有 `powermetrics` 能拿到，但 macOS 26 beta 上 `cpu_power = 0`（见第4条）。目前**无可用方案**，整机功耗用 PSTR 代替
- **待观察**：macOS 26 正式版 powermetrics 修复后可重新评估

### 13. IOReport Energy Model 通道大部分不更新（2026-06-28 实测）

- **现象**：IOReport 订阅 "Energy Model" 组后，仅 `GPU Energy` 通道有非零 delta。CPU Energy / EACC_CPU* / PACC* / ANE0 / DRAM0 / ISP0 / DCS0 全部返回 0。
- **根因**：未知。可能是 macOS 26 beta 的 bug（同 powermetrics `cpu_power=0`），也可能是 M1 Pro 的 IOReport 驱动在这些通道上不推送数据。这些通道名称存在（`IOReportChannelGetChannelName` 可读），但能量计数器始终不变（S1=S2 所有 offset 均相同）。
- **教训**：
  - **GPU 功耗可用**：`IOReportSimpleGetIntegerValue(ch, 0)` + `IOReportChannelGetUnitLabel(ch)` → nJ → watts
  - **CPU 功耗不可直接读**：需用 `PSTR整机 − GPU` 估算
  - **不要假设 IOReport 通道名存在即有效**，必须在目标机型上实测 delta
- **可用 API 函数**（全部通过 `dlopen("/usr/lib/libIOReport.dylib")` + `dlsym`）：
  - `IOReportCopyChannelsInGroup` → 获取通道列表（返回 CFDictionary）
  - `IOReportCreateSubscription` → 创建订阅（参数为 CFMutableDictionary）
  - `IOReportCreateSamples` → 采样
  - `IOReportCreateSamplesDelta` → 两次采样的差值
  - `IOReportSimpleGetIntegerValue(ch, 0)` → 读取通道元素值
  - `IOReportChannelGetChannelName` / `IOReportChannelGetUnitLabel` → 通道元数据
- **注意**：这些函数在 `libIOReport.dylib` 中，但**不导出链接符号**（dyld shared cache），只能 `dlsym` 动态获取，无法直接 `gcc -lIOReport` 链接。

---

### 14. IOReport `backlight report` 返回静态快照值，亮度变化不刷新（2026-06-28 实测）

- **现象**：`MicroAmps value` / `MilliNits value` / `UserBrightness value` 等通道无论亮度如何调节均不变。创建持久订阅后多次 `IOReportCreateSamples`，三次采样值完全相同。
- **根因**：未知。IOReport `backlight report` 在 M1 Pro + macOS 26 beta 下不推送实时更新。可能是系统的内部缓存机制，或此通道组不同于 `Energy Model`，不支持实时采样。
- **已尝试**：
  - IOReport 一次性订阅 + 单采样 → 静态
  - IOReport 持久订阅 + 多次采样 → 静态
  - IORegistry `AppleCLCD2` → `IOMFBBrightnessLevel` 同样静态
  - `DisplayServicesGetBrightness` → ✅ 实时可用，但只返回 0–1 百分比，无瓦数
- **教训**：IOReport 各通道组的行为不一致，不能假设"名称存在即可用"。`Energy Model` 仅 `GPU Energy` 实时更新；`backlight report` 全部静态。屏幕瓦数在 M1 Pro 上无法获取。

---

## 快速诊断

| 症状 | 先查 |
|------|------|
| 放电功耗为 0 | 检查是否读了 PDTR（应改 PSTR）|
| mode 乱跳 | 检查是否用了 B0AC/B0PS 判断 AC 状态 |
| 通知不弹 | 检查是否签名，Console 搜 `usernotificationsd` |
| UI 打开菜单后冻住 | 是否还在用 NSMenu（应改 NSPanel）|
| 续航一直"估算中" | kIOPSTimeToEmptyKey 返回 -1，改读 IORegistry TimeRemaining |
| 充电瓦数跳动 | 检查是否用了 B0AC × B0AV（应改 PSTR）|
| CPU/GPU 功耗恒为 0 | SMC 不提供，用 IOReport（GPU Energy 可用，CPU 暂不可用 → §13）|
| IOReport 通道无数据 | 仅在目标机型实测，Energy Model 仅 GPU Energy 更新，backlight report 全静态（→ §13、§14）|
| 屏幕/亮度数据不刷新 | IOReport backlight / IORegistry CLCD2 均返回静态值；DisplayServices 可读亮度%但无瓦数（→ §14）|
