# FanSense 版本记录

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
