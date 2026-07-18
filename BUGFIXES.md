# FanSense Bug 修复记录

> 代码审查后，对简单且不会引入新问题的 bug 进行修复。按严重等级排列。
> 最后更新：2026-07-18

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

## v1.2.1 审查修复（2026-07-18）

以下问题在本次代码审查中发现并已修复：

### BUG-007: build.sh heredoc 引号导致版本号不展开

- **严重度**: 高
- **文件**: `build.sh:40`
- **问题**: `cat > Info.plist <<'PLIST'` 带引号 heredoc 禁止变量替换，产物 `CFBundleVersion` / `CFBundleShortVersionString` 为字面 `${VERSION}`。
- **修复**: 去掉引号 → `<<PLIST`。
- **状态**: ✅ 已修复

### BUG-008: DMG 卸载仅匹配单一卷名

- **严重度**: 低
- **文件**: `build.sh:66`
- **问题**: `hdiutil detach /Volumes/FanSense` 单点卸载，当卷名为 "FanSense 1" / "FanSense 2" 时漏过。
- **修复**: 改为 `for v in /Volumes/FanSense*; do hdiutil detach "$v"; done` 通配卸载所有同名卷。
- **状态**: ✅ 已修复

### BUG-009: 充电模式 vs refresh 竞态

- **严重度**: 高
- **文件**: `main.swift`
- **问题**: `refresh()` 秒级运行，在充电 set 命令完成前读到 SMC mode=0 → 写入 `fanMode = .auto`。之后 set 落地但 UI 永久显示 "自动"、菜单不勾选，风扇实际满速——失同步且不可恢复。
- **修复**:
  - 引入 `writeInFlight` 计数器追踪进行中的异步写；sync 规则仅在 `writeInFlight == 0 && !fanView.pendingChange` 时生效。
  - 充电 set 改为与滑块一致的 3 次写确认+重试路径。
  - 充电/滑块均增加 per-attempt generation 检查，superseded 任务立即中止。
  - 新增反失同步恢复：`smcManual && fanMode == .auto` → 采用 `.manual`。
  - 滑块滑至最左 → 复用 `restoreAutoMode()`，统一路径且非阻塞。
- **状态**: ✅ 已修复

### BUG-010: 充电模式目标显示错误

- **严重度**: 高
- **文件**: `FanView.swift`
- **问题**: "目标 %.0f rpm" 标签读 `slider.doubleValue`（停在 min），实际 SMC target 为 max——显示错误。
- **修复**: `FanView.update()` 非 auto 模式下同步 slider 到 SMC target。
- **状态**: ✅ 已修复

### BUG-011: 写确认逻辑退化

- **严重度**: 高
- **文件**: `FanView.swift:76-99`, `main.swift:526-527`
- **问题**: `update(mode:)` 传 app 本地 `fanMode` 而非 SMC 派生的 manual 位。debounce 设 `fanMode = .manual` 后下一 refresh 就清 `pendingChange`，与写入是否落地无关——"SMC confirms" 沦为自证循环。
- **修复**: `update(mode:smcManual:)` 新增 smcManual 参数，确认清 latch 改用 SMC 实地值而非 app 本地值。
- **状态**: ✅ 已修复

### BUG-012: 滑块重试 vs 充电模式竞态

- **严重度**: 高
- **文件**: `main.swift:280-295`
- **问题**: `toggleChargingMode` 没 bump `setGeneration`，飞行中的滑块重试任务（最多 3×500ms）可能在充电设 max 后覆写回旧值。
- **修复**: toggleChargingMode 同步 bump generation；滑块重试每轮校验 generation，失效即中止。
- **状态**: ✅ 已修复

### BUG-013: 充电模式拔电不自退 + 无写确认

- **严重度**: 中
- **文件**: `main.swift`
- **问题**: 无拔电自动退出；充电模式同步 `runHelper` 阻塞主线程，无重试验证；叫 "充电模式" 易误导（实为满速锁定）。
- **修复**:
  - 充电模式下拔电 → `refresh()` 检测 `!bat.isOnAC` → 调 `restoreAutoMode()`。
  - 充电 set 改为 detached task + 3 次重试写确认 + generation guard。
  - 恢复分支改为 `restoreAutoMode()`，异步非阻塞，与滑块左滑公用路径。
- **状态**: ✅ 已修复

### BUG-014: SMC 失同步，手动模式不可恢复

- **严重度**: 中
- **文件**: `main.swift:518`
- **问题**: app 重启后若 SMC 残留 manual（上次崩溃/未清理），UI 显示 "自动" 且无法感知——不能调回手动，也不能用滑块控制。
- **修复**: Sync 规则新增 `smcManual && fanMode == .auto → .manual` 反失同步路径。同时将 slider 同步到 target，保持 UI 正确。
- **状态**: ✅ 已修复

### BUG-015: ensureHelper 路径注入

- **严重度**: 中
- **文件**: `main.swift:391`
- **问题**: `bundled` 路径原样拼入 `do shell script ... with administrator privileges`，路径含 `"` 或 `\` 即以 root 执行任意命令。AppleScript 层已有硬引号套壳，但壳内仍可逃逸。
- **修复**: 在拼 shell 字符串前对路径做 `\` → `\\`、`"` → `\"` 双重转义。
- **状态**: ✅ 已修复

### BUG-016: setuid helper IOReport 死代码

- **严重度**: 中
- **文件**: `fanhelper.c:12-41`
- **问题**: IOReport 全量 dlopen/dlsym 指针从未调用（`load_ioreport` 零引用），仅增加 setuid 二进制攻击面。
- **修复**: 完全删除 IOReport 加载代码及 `dlfcn.h` 依赖。helper version 同步 bump 至 4。
- **状态**: ✅ 已修复

### BUG-017: smc.c 不校验 SMC result 字段

- **严重度**: 中
- **文件**: `smc.c:74-93`
- **问题**: `read_key` 在 SMC 返回 status ≠ 0 时仍盲 memcpy 输出字节（key 不存在或权限不足时读到垃圾），由上层 `t > 0` 兜底。
- **修复**: `read_key` 在 READ_KEYINFO 和 READ_BYTES 后各检查 `out.result`，非零直接返回 -1。新增 `sp78` 类型支持（Intel Mac 温度格式），未知非 4 字节类型返回 -1。
- **状态**: ✅ 已修复

### BUG-018: 菜单右键不响应 Ctrl+左键

- **严重度**: 低
- **文件**: `main.swift:150-157`
- **问题**: macOS 惯例 Ctrl+左键应等同右键弹出上下文菜单，但 `statusClicked` 仅检查 `event.type` 不检查 modifier。
- **修复**: 追加 `(event.type == .leftMouseUp && event.modifierFlags.contains(.control))` 判断。
- **状态**: ✅ 已修复

---

## 待修复（审查发现但未动代码）

以下问题在审查中识别，因涉及架构调整或需进一步测试而暂缓：

| Bug ID | 严重度 | 简述 | 文件 |
|--------|--------|------|------|
| BUG-019 | 严重 | 定时器碰撞：t=60s 时 `dataTimer` 和 `bgSampleTimer` 同时触发并发 SMC 访问 | `main.swift:119-128` |
| BUG-020 | 严重 | `runHelper()` 吞掉所有错误，无日志无退出码检查 | `DataSources.swift:33-43` |
| BUG-021 | 高 | `smoothPath`/`interpolate`/`niceMax` 在 FanView 和 ChargeChartView 中重复 | `FanView.swift` / `ChargeChartView.swift` |
| BUG-022 | 高 | `makeCard` + `embedInCard` 的 content 子视图 resize 后不跟踪父尺寸 | `RoundedPanelView.swift` |
| BUG-023 | 中 | `FanView.h` 写死 322pt 与右列总高对齐，右列变化时静默断裂 | `FanView.swift:9` |
| BUG-024 | 中 | `updateIconHot` 两处调用（bgSample + refresh），可能短暂显示过期温度 | `main.swift:384, 452` |
| BUG-025 | 中 | `readNetwork` 只取流量最大的单接口，多网卡遗漏合计 | `DataSources.swift:211-248` |
| BUG-026 | 中 | `readDisk` 降级路径数值口径不一致（importantUsage vs freeSize） | `DataSources.swift:281-301` |
| BUG-027 | 低 | README.md macOS 版本要求不一致（正文 26+ vs Info.plist 15.0） | `README.md:39` |
| BUG-028 | 低 | `nvme_smart.c` 接口结构逆向自私有头文件，macOS 升级可能断裂 | `nvme_smart.c:47-56` |
