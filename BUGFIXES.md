# FanSense Bug 修复记录

> 代码审查后，对简单且不会引入新问题的 bug 进行修复。按严重等级排列。
> 最后更新：2026-07-17

---

## 高 (High)

### BUG-001: 强制解包崩溃风险

- **文件**: `ChargeChartView.swift:90`, `FanView.swift:246`
- **问题**: `fullCurve.copy() as! NSBezierPath` — `NSObject.copy()` 返回 `Any`，在极端图形上下文状态下可能返回非 `NSBezierPath` 类型，导致运行时崩溃。
- **修复**: 改为 `guard let clipPath = fullCurve.copy() as? NSBezierPath else { return }`，安全解包失败则跳过填充绘制。
- **状态**: ✅ 已修复

---

## 中 (Medium)

### BUG-002: 死代码 `FanView.setSliderValue`

- **文件**: `FanView.swift:107-109`
- **问题**: `setSliderValue` 方法包装了 `setSliderSilently`，但整个代码库中无任何调用点。当前滑块均在 `update()` 中通过 `setSliderSilently` 直接操作。
- **修复**: 删除该函数。
- **状态**: ✅ 已修复

### BUG-003: `diskBarView` 健康行用 `warnAt: 2` 规避阈值报警

- **文件**: `MetricBarView.swift`, `main.swift:224, 488`
- **问题**: SSD 健康行设置 `warnAt: 2, critAt: 2`，利用 `percent`（0-1）永远达不到 2 来规避状态文字和阈值颜色。这是 hack，表意不清。
- **修复**: 给 `MetricBarView.Entry` 增加 `showStatus: Bool = true` 字段。当 `false` 时，直接使用 `entry.color` 作为显示色，不绘制状态文字（"正常"/"较高"/"过载"），不评估 `warnAt`/`critAt` 阈值。SSD 健康行在 main.swift 中显式设置 `showStatus: false`。
- **状态**: ✅ 已修复

### BUG-004: `smc.c` 2 字节有符号整型被无符号扩展

- **文件**: `smc.c:103`
- **问题**: 2 字节 SMC 数据用 `((unsigned char)b[0] << 8) | (unsigned char)b[1]` 存入 `int`，高位零扩展。对带符号值（如电池电流 `B0AC`）会丢失负号，依赖 Swift 端 `Int16(truncatingIfNeeded:)` 做二次补救。
- **修复**: 改为 `(int16_t)(((unsigned char)b[0] << 8) | (unsigned char)b[1])`，在 C 层直接完成有符号扩展。
- **状态**: ✅ 已修复

---

## 低 (Low)

### BUG-005: 死代码 `print_backlight`

- **文件**: `fanhelper.c:43-105`
- **问题**: `print_backlight` 函数实现完整的 IOReport backlight 订阅+采样逻辑，但 `main()` 中无任何子命令可调用。编译产物包含该函数但无入口。
- **修复**: 删除 `print_backlight` 函数体。IOReport 函数指针及 `load_ioreport()` 保留，供后续 GPU Energy 通道集成使用（参见 DATA_SOURCES.md §1.3）。
- **状态**: ✅ 已修复

### BUG-006: `DESIGN.md` SystemBarView `barY` 公式错误

- **文件**: `DESIGN.md:126`
- **问题**: 文档写 `barY = TR + 4`，但实际代码为 `barY = rowTop + TR + 4`。`rowTop` 依赖父容器高度，文档公式缺少 `rowTop` 偏移。
- **修复**: 修正为 `barY = rowTop + TR + 4`，与 `SystemBarView.swift:74` 一致。
- **备注**: SystemBarView 已废弃，仅文档修正。
- **状态**: ✅ 已修复

---

## 待修复（审查发现但未动代码）

以下问题在审查中识别，因涉及架构调整或需进一步测试而暂缓：

| Bug ID | 严重度 | 简述 | 文件 |
|--------|--------|------|------|
| BUG-007 | 严重 | 定时器碰撞：t=60s 时 `dataTimer` 和 `bgSampleTimer` 同时触发并发 SMC 访问 | `main.swift:119-128` |
| BUG-008 | 严重 | `runHelper()` 吞掉所有错误，无日志无退出码检查 | `DataSources.swift:33-43` |
| BUG-009 | 高 | `smoothPath`/`interpolate`/`niceMax` 在 FanView 和 ChargeChartView 中重复 | `FanView.swift` / `ChargeChartView.swift` |
| BUG-010 | 高 | `makeCard` + `embedInCard` 的 content 子视图 resize 后不跟踪父尺寸 | `RoundedPanelView.swift` |
| BUG-011 | 中 | `FanView.h` 写死 322pt 与右列总高对齐，右列变化时静默断裂 | `FanView.swift:9` |
| BUG-012 | 中 | `updateIconHot` 两处调用（bgSample + refresh），可能短暂显示过期温度 | `main.swift:384, 452` |
| BUG-013 | 中 | `readNetwork` 只取流量最大的单接口，多网卡遗漏合计 | `DataSources.swift:211-248` |
| BUG-014 | 中 | `readDisk` 降级路径数值口径不一致（importantUsage vs freeSize） | `DataSources.swift:281-301` |
| BUG-015 | 低 | README.md macOS 版本要求不一致（正文 26+ vs Info.plist 15.0） | `README.md:39` |
| BUG-016 | 低 | `nvme_smart.c` 接口结构逆向自私有头文件，macOS 升级可能断裂 | `nvme_smart.c:47-56` |
