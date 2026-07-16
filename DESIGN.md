# FanSense — 设计规范 & 私有 UI 库

> 本文档描述 FanSense 的视觉语言、设计 token、组件库及布局规则。
> 新增视图时以此为准，不要另起炉灶。
> 最后更新：2026-06-27（同步当前代码状态）

---

## 一、设计 Token

### 1.1 尺寸

```swift
let W:       CGFloat = 560    // 面板总宽，双列布局
let hPad:    CGFloat = 8      // 卡片水平边距
let colGap:  CGFloat = 8      // 双列列间距
let GAP:     CGFloat = 10     // 卡片间距
let TR:      CGFloat = 2.5    // 进度条轨道高度
let CR:      CGFloat = 1.25   // 进度条圆角半径
let CARD_R:  CGFloat = 14     // 卡片圆角
let PANEL_R: CGFloat = 18     // 面板外框圆角
```

卡片内上下填充：`vPad = 8`（在 `makeCard` 内部定义）。

**双列布局**：左列（电池/能效/风扇）与右列（温度/处理器·内存/网络/磁盘）并排，列宽 = `(W - hPad*2 - colGap) / 2`。

### 1.2 文字

| 用途 | 字号 | 字重 | 字体 | 颜色 |
|------|------|------|------|------|
| 大数值（温度/功耗/占用率/转速） | 22pt | semibold | monospacedDigit | 语义色（见 §1.3）|
| 副标签（CPU / 内存 / 下载…） | 10pt | regular | system | secondaryLabelColor |
| 区段标题（处理器·内存…） | 9pt | regular | system | tertiaryLabelColor |
| Header 型号名 | 13pt | regular | system | labelColor |
| Header 运行时间 | 10pt | regular | system | secondaryLabelColor |
| 模式标签（风扇自动/手动） | 22pt | semibold | system | labelColor / systemOrange |
| 进程名 | 12pt | regular | system | labelColor |
| 进程占用率 | 11pt | regular | monospacedDigit | 语义色 |

**规则**
- 所有数字必须用 `monospacedDigitSystemFont` 避免宽度抖动。
- 大数值统一 **22pt** semibold，小副标签统一 10pt regular。
- 不允许使用 14pt / 20pt 或其他中间值（历史遗留已清除）。

### 1.3 语义色

每种数据类型绑定固定的系统色，**不能随意换色**。

| 数据类型 | 正常色 | 警告色 | 危险色 |
|----------|--------|--------|--------|
| CPU 占用 | systemPurple | systemOrange（≥70%）| systemRed（≥90%）|
| 内存占用 | systemBlue | systemOrange（pressure≥0.6）| systemRed（≥90%）|
| 温度 | systemBlue | systemOrange（warn阈值）| systemRed（crit阈值）|
| 网络（下载/上传） | systemTeal | — | — |
| 磁盘占用 | systemIndigo | systemOrange（≥80%）| systemRed（≥90%）|
| 风扇（自动） | systemBlue | — | — |
| 风扇（手动） | systemOrange | — | — |
| 充电图表 Mode 0 放电 | systemYellow | — | — |
| 充电图表 Mode 1 充电 | systemGreen | — | — |
| 充电图表 Mode 2 满电 | systemBlue | — | — |
| 能效 高效 | systemGreen | — | — |
| 能效 中等 | systemOrange | — | — |
| 能效 高耗 | systemRed | — | — |
| GPU 占用 | systemGreen | systemOrange（≥70%）| systemRed（≥90%）|

**通用阈值规则**：`≥ 0.95` → systemRed，`≥ 0.85` → systemOrange（无特殊说明时默认）。

### 1.4 背景 & 层叠

| 层级 | 实现 | 说明 |
|------|------|------|
| 面板底层 | `NSVisualEffectView`，`.hudWindow` material | 毛玻璃模糊 |
| 卡片背景 | `NSColor(white: 1, alpha: 0.06)` | 极低透明白膜，亮暗模式自适应 |
| 进度条轨道 | `NSColor.separatorColor.withAlphaComponent(0.25)` | 中性轨道 |
| 进度条填充 | 语义色 `.withAlphaComponent(0.7)` | 半透明，避免过重 |
| 分隔线 | `NSColor.separatorColor.withAlphaComponent(0.4)` | 组内分割 |

---

## 二、私有 UI 组件库

### 2.1 `RoundedPanelView`

```
NSVisualEffectView
  material: .hudWindow
  cornerRadius: PANEL_R (18)
  blendingMode: 系统默认
```

- 面板的唯一外层视图，承载 `NSScrollView`。
- 不要在此层做任何数据渲染。

---

### 2.2 `HeaderView`

**高度**：`48pt`（静态）

**布局**：
```
┌──────────────────────────────┐
│      MacBook Pro M1 Pro      │  13pt regular labelColor，居中
│       运行 3 天 4 小时        │  10pt regular secondaryLabelColor，居中
└──────────────────────────────┘
```

**属性**：`modelName: String`，`uptimeLine: String`

---

### 2.3 `SystemBarView`（已废弃，代码保留备用）

> **注意**：网络和磁盘已分别迁移至 `NetBarView` 和 `MetricBarView`（磁盘）。`SystemBarView` 当前未被 `cardGroups` 引用，代码保留备用。

**原用途**：网络、磁盘等双列数据卡片（无状态文字需求的纯数值展示）。

**高度公式**：`rowH(52) + headH(16) = 68pt`（始终只有 1 视觉行，2 列并排）

**单元格布局（每列宽 = (W - IP×2) / 2 - 8）**：
```
┌──────────────┐
│  74%          │  ← 20pt semibold mono，语义色，距顶 24pt
│  CPU          │  ← 10pt regular secondary，距顶 10pt
│▓▓▓▓▓░░░░░░░│  ← TR=2.5 轨道，底部 barY = TR+4
└──────────────┘
```

**数据模型**：
```swift
struct Row {
    var label:    String
    var valueStr: String
    var percent:  Double   // 0–1，< 0 表示无进度条
    var color:    NSColor
}
```

**阈值色覆盖**：`percent ≥ 0.95 → systemRed`，`≥ 0.85 → systemOrange`，否则用 `row.color`。

---

### 2.3b `MetricBarView`  ← 处理器·内存 / 磁盘 通用

**用途**：CPU/内存（sectionTitle="处理器·内存"）及磁盘（sectionTitle="磁盘"）卡片，与 TempBarView 采用相同排版语言。

**高度公式**：`headH(16) + count × rowH(56) + (count-1) × rowGap(8)`
- 2 行 = `16 + 2×56 + 8 = 136pt`

**单行布局（全宽，从上到下）**：
```
CPU                   ← 9pt regular tertiary，左上角小标题
74%            正常   ← 22pt semibold mono（左，语义色）+ 22pt semibold（右，状态色）
▓▓▓▓▓░░░░░░░        ← barH=5，圆角 2.5，全宽，底部 barY = rowBottom+4
```

**状态文字与颜色**：

| 状态 | 颜色 | CPU 阈值 | 内存阈值 |
|------|------|----------|----------|
| 正常 | systemGreen  | < 70%  | < 60%  |
| 较高 | systemOrange | 70–89% | 60–89% |
| 过载 | systemRed    | ≥ 90%  | ≥ 90%  |

磁盘行：已用（warnAt=0.80 critAt=0.90）显示进度条；可用（percent=-1）不画进度条，仅显示数值。

**数据模型**：
```swift
struct Entry {
    var label:    String
    var valueStr: String
    var percent:  Double    // 0–1；< 0 表示不画进度条
    var color:    NSColor   // 正常色
    var warnAt:   Double    // percent 阈值（橙）
    var critAt:   Double    // percent 阈值（红）
}
```

**使用示例**：
```swift
// 占用（CPU·GPU·内存）
metricBarView.sectionTitle = "占用"
metricBarView.entries = [
    .init(label:"CPU",  valueStr:"74%", percent:0.74, color:.systemPurple, warnAt:0.70, critAt:0.90),
    .init(label:"GPU",  valueStr:"13%", percent:0.13, color:.systemGreen,  warnAt:0.70, critAt:0.90),
    .init(label:"内存", valueStr:"61%", percent:0.61, color:.systemBlue,   warnAt:0.60, critAt:0.90),
]

// 磁盘
diskView.sectionTitle = "磁盘"
diskView.entries = [
    .init(label:"已用", valueStr:"512 GB", percent:0.68, color:.systemIndigo, warnAt:0.80, critAt:0.90),
    .init(label:"可用", valueStr:"245 GB", percent:-1,   color:.systemIndigo, warnAt:0.80, critAt:0.90),
]
```

---

### 2.4 `TempBarView`

**高度**：`headH(16) + 3×rowH(56) + 2×rowGap(8) = 16+168+16 = 200pt`（含 sectionTitle）

> 3 行：CPU / GPU / 电池温度

**单行布局（全宽，从上到下）**：
```
CPU                   ← 9pt regular tertiary，左上角小标题
72°            正常   ← 22pt semibold mono（左，语义色）+ 22pt semibold（右，状态色）
▓▓▓▓▓░░░░░░░        ← barH=5，圆角 2.5，全宽
```

`sectionTitle = "温度"`，headH=16，rowH=56，rowGap=8。

**阈值配置**：

| 行 | warnAt | critAt | maxTemp |
|----|--------|--------|---------|
| CPU  | 60 | 95 | 105 |
| GPU  | 60 | 95 | 105 |
| 电池 | 35 | 45 |  60 |

**状态文字与颜色**：

| 状态 | 颜色 | 温度 |
|------|------|------|
| 正常 | systemGreen  | < warnAt  |
| 高温 | systemOrange | warnAt–(critAt-1) |
| 降频 | systemRed    | ≥ critAt  |
---

### 2.5 `BatteryBarView`

**高度**：`244pt`（始终展开，含曲线图）
- topPad = 20pt（顶部留白）
- rowH = 56pt（百分比 + 状态 + 电池条，同 TempBarView 行高）
- 曲线图区 = 144pt（含内边距）

**布局**：
```
┌──────────────────────────────────┐
│                                  │  ← 20pt 顶部留白
│ 86%                   放电中     │  ← 32pt bold mono 百分比 + 22pt semibold 状态
│ 剩余续航 3h20m · 18.4W           │  ← 10pt secondary 副信息
│ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░[==]         │  ← 12pt 电池条（保持原样）
│                                  │
│  ╱╲  ╱╲                         │
│ ╱  ╲╱  ╲  15.2W                 │  ← 144pt 充电历史曲线（60s 窗口）
│ ╱        ╲                       │     Y轴标尺左侧、功耗角标右上
│╱          ╲──────                │
└──────────────────────────────────┘
```

**powerMode 颜色**：0 放电→systemYellow, 1 充电→systemGreen, 2 满电→systemBlue。
无展开/折叠，无 section title。

---

### 2.6 `ChargeChartView`

**高度**：`144pt`（嵌入 BatteryBarView，始终可见）

每秒 push 一个 `Sample(watts, mode)`，60s 滑动窗口。折线颜色跟随 mode。
内部边距：leftPad=22（Y轴标签）、rightPad=4、topPad=10、botPad=20。
Y 轴标签在 plot 左侧外部，当前值角标固定右上角。

---

### 2.7 `EfficiencyView`

**高度**：`68pt`（放电时显示，充电/满电时 `isHidden = true`）

**布局**：2 列
```
  18.3W           高效          ← 22pt semibold，左均值瓦数，右等级文字，均用 gradeColor
  均值功耗        约3h20m续航   ← 10pt regular secondary
  ▓▓▓░░░░░░░░░░░░░░░░░░       ← 功耗比例条（满值 = 50W），颜色跟随等级
```

**等级逻辑**（取功耗轴与续航轴较差的一级）：

| 等级 | 颜色 | 功耗轴 | 续航轴 |
|------|------|--------|--------|
| 高效 | systemGreen | < 10W | ≥ 4h |
| 中等 | systemOrange | 10–15W | 2–4h |
| 高耗 | systemRed | > 15W | < 2h |

---

### 2.8 `FanSliderView`

**高度**：`96pt`（静态）

**布局**：
```
  1850 RPM   [自动]            ← 22pt semibold mono 转速 + 22pt semibold 模式标签
  ████████████████░░░░░░      ← NSSlider，自动=systemBlue，手动=systemOrange
  1200                  4700  ← 最小/最大 RPM，9pt tertiary
```

---

### 2.9 `NetBarView`  ← 网络专用

**用途**：显示下载/上传速率，无进度条，无状态文字。

**高度**：`headH(16) + rowH(56) = 72pt`

**布局**：
```
[sectionTitle="网络"]
↓ 120 KB/s          ↑ 45 KB/s   ← 下载左对齐，上传右对齐，22pt semibold mono
下载                  上传       ← 10pt regular secondary
```

数据来源：`getifaddrs` 累加字节差值，每秒更新。

---

## 三、布局系统

### 3.1 卡片组装

所有卡片由 `makeCard(_ views: [NSView])` 统一生成：

```
card高度 = vPad(8) + 各视图高度之和 + vPad(8)
视图从下到上叠放（NSView 坐标原点在左下角）
水平边距 = hPad = 8
卡片圆角 = CARD_R = 14
卡片背景 = NSColor(white:1, alpha:0.06)
```

### 3.2 卡片顺序（双列布局）

面板宽 W=560，左右两列并排。左列从上到下，右列从上到下。

| 列 | 顺序 | 卡片 | 视图 | 视图高（不含vPad）| 卡片高（含vPad×2）|
|----|------|------|------|------------------|------------------|
| 左 | 1 | 电池 | BatteryBarView | 244pt（始终展开含曲线图）| 260pt |
| 左 | 2 | 能效 | EfficiencyView | 68pt（放电显示）| 84pt |
| 左 | 3 | 风扇 | FanSliderView | 96pt | 112pt |
| 右 | 1 | 温度 | TempBarView | 200pt | 216pt |
| 右 | 2 | 占用（CPU·GPU·内存）| MetricBarView | 200pt（3 行）| 216pt |
| 右 | 3 | 网络 | NetBarView | 72pt | 88pt |
| 右 | 4 | 磁盘 | MetricBarView | 136pt | 152pt |

卡片间距 `GAP = 10pt`，Header 独立在最顶部（无卡片背景，高度 48pt）。

### 3.3 面板滚动

内容总高 > 屏幕可用高度时，`NSScrollView` 自动启用竖向滚动条（`autohidesScrollers = true`，无边框，无背景）。

---

## 四、新增视图规则

1. **高度静态化**：每个视图必须有 `static let h` 或 `static func height()` 返回精确高度，不能依赖 Auto Layout。
2. **数字用 monospacedDigit**：所有数值显示用 `NSFont.monospacedDigitSystemFont(ofSize:weight:)`。
3. **大值 22pt**：主要数值统一 22pt semibold，副标签 10pt regular，区段标题 9pt regular。不允许使用 20pt 或其他中间值。
4. **颜色遵循语义色表**：对应到 §1.3 的数据类型，不新增自定义颜色。
5. **双列布局**：2 个并列数据用 2 列，列宽 = `(W - hPad*2 - colGap) / 2`。
6. **进度条**：轨道 TR=2.5，圆角 CR=1.25，填充色用语义色 `.withAlphaComponent(0.7)`，轨道色 `separatorColor.withAlphaComponent(0.25)`，`barY = TR + 4`。
7. **不用 Auto Layout / NSStackView**：全部手动 frame，坐标原点在左下角。
8. **隐藏逻辑**：条件性显示的视图用 `isHidden`，高度不变（`makeCard` 高度已固定）。
