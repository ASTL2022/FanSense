# Apple Design 改进规划

> 审查日期：2026-07-18
> 审查标准：[Apple Design](https://developer.apple.com/design/human-interface-guidelines) + Emil Kowalski apple-design skill

---

## 即做（★级，共 9 行）

### 1. slider debounce 200ms
- **文件**：`main.swift:265`
- **After**：`TimeInterval: 0.5` → `0.2`
- **风险**：无。SMC 每秒最多 5 次写，远低于 flood 阈值

### 2. Reduced Motion 检测
- **文件**：`main.swift:26-31`（StatusIconView）
- **After**：`spinning && !reduceMotion`，停止旋转时用静态透明度区分
- **风险**：零。`NSWorkspace.accessibilityDisplayShouldReduceMotion` 不会变 nil

### 3. 触觉反馈
- **文件**：`main.swift:265-320`（slider debounce handler + toggleChargingMode + restoreAutoMode）
- **After**：滑块放置 → `.alignment` haptic；模式切换 → `.levelChange` haptic
- **风险**：零。AppKit haptic API 稳定

### 4. 目标标签颜色去硬 alpha
- **文件**：`FanView.swift:185`
- **After**：`accent.withAlphaComponent(0.8)` → `accent.withAlphaComponent(0.7)` （微调，Vitrum 材质下可读性更好）
- **风险**：零

---

## 待评估（★★级，共 ~40 行）

### 5. 面板进场动画
- **文件**：`main.swift:206-212`（showPanel）
- **After**：`NSAnimationContext.runAnimationGroup` scale 0.9→1.0 + opacity 0→1，origin 从 statusItem 按钮
- **风险**：低。需测试快速连续点按

### 6. 面板退场动画
- **文件**：`main.swift:215-219`（hidePanel）
- **After**：scale 1.0→0.9 + opacity 1→0 → completionBlock → `orderOut`
- **风险**：中。需处理动画中 clickMonitor 时序

---

## 暂缓（★★★★级，~80 行）

### 7. Dynamic Type 支持
- **文件**：所有 View 文件
- **做法**：换 `NSFont.preferredFont(forTextStyle:)` + `NSFontTextStyle` observer + 布局自撑开
- **风险**：高。AppKit Dynamic Type 生态弱，会破坏现有固定高度布局设计
- **建议**：等架构重构时统一处理

---

## 执行记录

| 项 | 日期 | 状态 |
|---|---|---|
| 1. slider debounce 200ms | 2026-07-18 | ✅ |
| 2. Reduced Motion | 2026-07-18 | ✅ |
| 3. 触觉反馈 | 2026-07-18 | ✅ |
| 4. 目标标签 alpha | 2026-07-18 | ✅ |
| 5. 面板进场动画 | 2026-07-18 | ✅ |
| 6. 面板退场动画 | 2026-07-18 | ✅ |
| 7. Dynamic Type | — | 🔲 (暂缓) |
