# FanSense

macOS menu bar fan control & system monitor for Apple Silicon Macs. Real-time temperature, power draw, CPU/GPU/memory usage, manual fan speed control — wrapped in a Liquid Glass panel.

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-orange)
![Swift](https://img.shields.io/badge/swift-5.9+-red)
![License](https://img.shields.io/badge/license-MIT-green)

> 中文文档: [README_CN.md](README_CN.md)

---

## Why FanSense

Most system monitors show you *what's happening*. FanSense tells you *what it means*.

- **Power efficiency rating** — none of the popular tools do this. FanSense calculates your Mac's energy grade based on real-time wattage and battery context.
- **PSTR + IOReport dual-source power tracking** — whole-system power from SMC, GPU power from IOReport, overlaid on a 60-second live chart.
- **Liquid Glass design** — built with macOS 26 glass panel APIs, not a hacked-together SwiftUI approximation.

| Feature | Stats | iStat Menus | Macs Fan Control | FanSense |
|------|:--:|:--:|:--:|:--:|
| SMC fan control | ✅ | ✅ | ✅ | ✅ |
| Power efficiency rating | ❌ | ❌ | ❌ | ✅ |
| PSTR whole-system power | ❌ | ❌ | ❌ | ✅ |
| IOReport GPU power | ❌ | ❌ | ❌ | ✅ |
| Battery energy grade | ❌ | ❌ | ❌ | ✅ |
| Liquid Glass panel | ❌ | ❌ | ❌ | ✅ |
| Open source | ✅ | ❌ | ❌ | ✅ |

---

## Features

### Real-time Monitoring
- **Temperature**: CPU / GPU / Battery, with color-coded threshold alerts
- **Power Tracking**: Whole-system power (PSTR) + GPU power (IOReport) + 60-second live chart
- **Battery**: Percentage, remaining time, charge state, energy efficiency grade
- **Performance**: CPU / GPU / Memory usage with health rating (Normal / High / Critical)
- **Network**: Real-time download/upload speed
- **Disk**: Used / free space on root partition

### Fan Control
- **Auto mode**: System default thermal management
- **Manual mode**: Precise speed control via slider (1200–4700 RPM)
- **Dynamic icon**: Menu bar icon rotation speed mirrors actual fan RPM

### Design
- **Liquid Glass panel**: Native `NSPanel` with HUD material, adaptive light/dark mode
- **Dual-column layout**: 560pt width — battery/efficiency/fan on left, temps/usage/network/disk on right
- **Semantic color system**: CPU purple, Memory blue, GPU green, Network cyan, Disk indigo — auto shifts to orange/red on threshold breach
- **Flicker-free**: Monospaced digits + frame-based layout, no jitter at 1s refresh

---

## Requirements

- **OS**: macOS 15+ (Sequoia or later); Liquid Glass features require macOS 26+
- **Processor**: Apple Silicon (M1 / M1 Pro / M1 Max / M2 / M3 / M4 series)
- **Permissions**: Root access required for fan speed control (via `fanhelper` helper binary)

> Intel Macs are not supported — SMC key names and IOReport channels differ from Apple Silicon.

---

## Installation

Build from source:

```bash
git clone https://github.com/ASTL2022/FanSense.git
cd FanSense
chmod +x build.sh
./build.sh
```

The build script compiles the Swift app and C helper, then packages everything into `FanControl.app`.

---

## Quick Start

1. Click the fan icon in the menu bar to open the panel
2. Drag the fan slider to your desired RPM — takes effect immediately
3. Click "Restore Auto" to return to system thermal management
4. Click "Quit" to exit

### Panel Layout

```
┌─────────────────────────────────┐
│      MacBook Pro M1 Pro         │
│      Uptime 3d 4h               │
├──────────────┬──────────────────┤
│ Battery      │ Temperature      │
│  86% on bat  │  CPU 72°  OK     │
│  3h20m left  │  GPU 58°  OK     │
│  chart       │  Bat 32°  OK     │
├──────────────┼──────────────────┤
│ Efficiency   │ Usage            │
│  18.3W  HIGH │  CPU 74%  OK     │
│              │  GPU 13%  OK     │
│              │  Mem 61%  OK     │
├──────────────┼──────────────────┤
│ Fan          │ Network          │
│  1850 RPM    │  ↓ 120 KB/s      │
│  [slider]    │  ↑ 45 KB/s       │
│              ├──────────────────┤
│              │ Disk             │
│              │  Used 512 GB     │
│              │  Free 245 GB     │
└──────────────┴──────────────────┘
│ [Restore Auto]    [Quit]        │
└─────────────────────────────────┘
```

### Alert Thresholds

| Metric | OK | Warning | Critical |
|------|------|------|------|
| CPU Temp | < 60°C | 60–94°C | ≥ 95°C |
| GPU Temp | < 60°C | 60–94°C | ≥ 95°C |
| Battery Temp | < 35°C | 35–44°C | ≥ 45°C |
| CPU Usage | < 70% | 70–89% | ≥ 90% |
| GPU Usage | < 70% | 70–89% | ≥ 90% |
| Memory Usage | < 60% | 60–89% | ≥ 90% |
| Disk Usage | < 80% | 80–89% | ≥ 90% |

---

## Architecture

### Core Components

**Swift App** (`main.swift` + view components)
- `AppController` — lifecycle, timers, panel management
- Views: `HeaderView`, `BatteryBarView`, `ChargeChartView`, `EfficiencyView`, `FanSliderView`, `TempBarView`, `MetricBarView`, `NetBarView`

**C Helper** (`fanhelper.c`)
- SMC read/write via `IOKit` (`IOServiceOpen`)
- Commands: `fan`, `fan <rpm>`, `temp <key>`, `power`

**Data Layer** (`DataSources.swift`)
- **Power**: SMC `PSTR` + IOReport GPU Energy
- **Temperature**: SMC `TC0x` / `Tg0D` / `TB0T`
- **CPU**: `host_processor_info` with delta calculation
- **Memory**: `host_statistics64` + `sysctl hw.memsize`
- **GPU**: IORegistry `AGXAccelerator` → Device Utilization %
- **Network**: `getifaddrs` with byte delta ÷ time interval
- **Disk**: `statvfs("/")`
- **Battery**: `IOPowerSources` + IORegistry `AppleSmartBattery`

### Refresh Strategy

- **Fast** (1s): temperature, power, CPU/GPU/memory, network, fan RPM
- **Slow** (30s): battery state, remaining time, disk usage

### Permission Model

- **No root needed**: reading temperature, power, usage stats, network, disk
- **Root required**: writing SMC (fan speed control) — delegated to `fanhelper` via pipe IPC

---

## Documentation

- **[DATA_SOURCES.md](DATA_SOURCES.md)** — API origins, field definitions, known limitations for every metric
- **[DESIGN.md](DESIGN.md)** — UI design tokens, component library, layout rules
- **[PITFALLS.md](PITFALLS.md)** — development gotchas: SMC quirks, NSPanel refresh, IOReport channels

---

## FAQ

**Why does it need my password?**  
Fan speed control requires SMC write access, which macOS restricts to root. The `fanhelper` binary runs as root; the main app communicates with it via pipe.

**Does manual fan speed persist?**  
Yes. It stays at the set RPM until you click "Restore Auto" or reboot.

**Intel Mac support?**  
No. SMC key names (`PCPU` / `PGPU`) and IOReport channels differ from Apple Silicon.

**macOS 26 beta battery time wrong?**  
macOS 26 beta has a known bug where `kIOPSTimeToEmptyKey` returns -1. FanSense reads `AppleSmartBattery` → `TimeRemaining` from IORegistry instead.

**Why is CPU power estimated?**  
Apple Silicon's IOReport `CPU Energy` channel doesn't update on current macOS. FanSense approximates: `CPU ≈ PSTR(total) − GPU`.

**External display power?**  
Not supported. All real-time display power APIs on M1 Pro return static snapshots, not live wattage values.

---

## Roadmap

### Done
- [x] Menu bar icon + NSPanel real-time panel
- [x] Temperature / power / battery / fan / CPU / GPU / memory / network / disk
- [x] Manual fan speed control
- [x] 60-second power history chart
- [x] Energy efficiency rating
- [x] Semantic color system + threshold alerts
- [x] Dynamic rotating icon (RPM-mapped)
- [x] Liquid Glass panel design

### Planned
- [ ] Custom fan curve (temperature → RPM mapping)
- [ ] History export (CSV / JSON)
- [ ] Multi-fan support (MacBook Pro 16" dual fan)
- [ ] Notification Center integration
- [ ] Headless CLI mode

---

## Credits

Built with reference to:

- [SMCKit](https://github.com/beltex/SMCKit) — SMC read/write primitives
- [iStat Menus](https://bjango.com/mac/istatmenus/) — UI design inspiration
- Apple IOKit / IOReport framework documentation
- [powermetrics](https://gist.github.com/samlown/5404439) — power monitoring exploration

---

## License

MIT License — see [LICENSE](LICENSE).

---

## Author

dr.t @ MarsCandyBox

Issues and pull requests welcome.
