# FanSense 版本记录

---

## v1.3.0 (2026-08-09)

### 性能
- 监控（风扇/温度/功耗）改为进程内直接读 SMC，不再每次 fork `fanhelper` 子进程
- 面板关闭时轮询降频至 30 秒，且只读风扇数据（`read`），不再读全部传感器
- 菜单栏风扇图标动画增加状态变化判断，避免无谓触发动画
- `fanhelper` 仅保留写转速（`set`/`auto`）与 SMART/版本校验

---

## v1.2.0 (2026-07-17)

### 修复
- 修复图表强制解包 `as! NSBezierPath` 潜在崩溃 → 改用 `guard let as?` 安全解包
- 修复 `smc.c` 2 字节 SMC 数据有符号扩展问题 → 改用 `int16_t`
- 修复 `MetricBarView` SSD 健康行 `warnAt:2` hack → 新增 `showStatus` 标志
- 修正 `DESIGN.md` SystemBarView `barY` 公式文档

### 清理
- 删除 `FanView.setSliderValue` 死代码
- 删除 `fanhelper.c` `print_backlight` 死代码（IOReport 基础设施保留）

---

## v1.1.0 (2026-07-16)

- 首个发布版本
- 菜单栏温度/功耗/使用率/电池/风扇监控
- Apple Silicon 风扇手动调速
- 60s 历史曲线（风扇 RPM / 功耗）
- 能效评级
- NVMe SMART SSD 健康
