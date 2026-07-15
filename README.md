# FanSense

A menu bar fan control and system monitor for Apple Silicon Macs. Shows temperature, power draw, CPU/GPU/memory usage, and lets you set fan speed manually.

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-orange)
![Swift](https://img.shields.io/badge/swift-5.9+-red)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

> 中文文档: [README_CN.md](README_CN.md)

---

## Features

### Monitoring
- **Temperature**: CPU / GPU / Battery, with color-coded threshold alerts
- **Power**: whole-system power (SMC PSTR) + GPU power (IOReport), 60-second live chart
- **Battery**: percentage, remaining time, charge state, energy efficiency grade
- **Usage**: CPU / GPU / memory with status rating
- **Network**: real-time download/upload speed
- **Disk**: usage of the root partition + SSD health from NVMe SMART (wear level)

### Fan Control
- **Auto mode**: system default thermal management
- **Manual mode**: set RPM with a slider; drag to minimum to hand control back to the system
- **History chart**: 60-second RPM curve, colored by mode (blue = auto, orange = manual)
- **Menu bar icon**: rotates while the fan is actually spinning; switches to a flame when CPU/GPU ≥ 80°C

### UI
- Native `NSPanel` with glass material, adapts to light/dark mode
- Two-column layout, monospaced digits, flicker-free 1s refresh
- Right-click the menu bar icon to quit

---

## Requirements

- **OS**: macOS 15+ (glass panel effects require macOS 26+)
- **Processor**: Apple Silicon
- **Permissions**: root is required once to install the `fanhelper` binary (fan speed writes go through SMC)

> Intel Macs are not supported — SMC key names and IOReport channels differ.

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

Install the helper (first time only):

```bash
sudo cp fanhelper /usr/local/bin/fanhelper
sudo chown root:wheel /usr/local/bin/fanhelper
sudo chmod u+s /usr/local/bin/fanhelper
```

---

## Usage

1. Click the fan icon in the menu bar to open the panel
2. Drag the fan slider to the desired RPM — takes effect after a short debounce
3. Drag the slider to the far left to restore automatic thermal management
4. Right-click the menu bar icon → Quit (fan control is returned to the system on exit)

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
| SSD Health | ≥ 90% | 70–89% | < 70% |

---

## Architecture

**Swift App** (`main.swift` + view components)
- `AppController` — lifecycle, timers, panel management
- Views: `BatteryBarView`, `ChargeChartView`, `EfficiencyView`, `FanView`, `TempBarView`, `MetricBarView`, `NetBarView`

**C Helper** (`fanhelper.c`, `smc.c`, `nvme_smart.c`)
- SMC read/write via IOKit
- NVMe SMART via `IONVMeSMARTUserClient` plug-in (internal SSD only, no root needed)
- Commands: `read` / `sensors` / `all` / `smart` / `set <rpm>` / `auto`

**Data Layer** (`DataSources.swift`)
- **Power**: SMC `PSTR` + IOReport GPU Energy
- **Temperature**: SMC `TC0x` / `Tg0D` / `TB0T`
- **CPU**: `host_processor_info` with delta calculation
- **Memory**: `host_statistics64` + `sysctl hw.memsize`
- **GPU**: IORegistry `AGXAccelerator` → Device Utilization %
- **Network**: `getifaddrs` with byte delta ÷ time interval
- **Disk**: `volumeAvailableCapacityForImportantUsage` (matches System Settings)
- **Battery**: `IOPowerSources` + IORegistry `AppleSmartBattery`

### Refresh Strategy

- **Fast** (1s, panel open): temperature, power, usage, network, fan RPM
- **Slow** (30s): battery state, disk usage
- **Panel closed**: fan state sampled every 10s (for the icon), power every 60s; SMART is read once at launch

### Permission Model

- **No root needed**: all monitoring (temperature, power, usage, network, disk, SMART)
- **Root required**: writing SMC (fan speed) — delegated to the setuid `fanhelper` binary

---

## Documentation

- **[DATA_SOURCES.md](DATA_SOURCES.md)** — API origins, field definitions, known limitations for every metric
- **[DESIGN.md](DESIGN.md)** — UI design tokens, component library, layout rules
- **[PITFALLS.md](PITFALLS.md)** — development gotchas: SMC quirks, NSPanel refresh, IOReport channels

---

## FAQ

**Why does it need my password?**  
Fan speed control requires SMC write access, which macOS restricts to root. The `fanhelper` binary runs setuid root; monitoring itself needs no privileges.

**Does manual fan speed persist?**  
It stays at the set RPM until you slide back to minimum, quit the app, or reboot. The app restores auto mode on exit.

**Intel Mac support?**  
No. SMC key names and IOReport channels differ from Apple Silicon.

**Why is CPU power estimated?**  
Apple Silicon's IOReport `CPU Energy` channel doesn't update on current macOS. FanSense approximates: `CPU ≈ PSTR(total) − GPU`.

**SSD health shows nothing?**  
SMART is only available for the internal NVMe drive, and requires the current `fanhelper` to be installed.

---

## Roadmap

- [ ] Custom fan curve (temperature → RPM mapping)
- [ ] History export (CSV / JSON)
- [ ] Multi-fan support (MacBook Pro 16" dual fan)
- [ ] Headless CLI mode

---

## Credits

- [SMCKit](https://github.com/beltex/SMCKit) — SMC read/write primitives
- Apple IOKit / IOReport framework documentation
- [powermetrics](https://gist.github.com/samlown/5404439) — power monitoring exploration

---

## License

GPL-3.0 — see [LICENSE](LICENSE). Versions up to v1.0.0 were released under MIT.

---

## Author

dr.t @ MarsCandyBox

Issues and pull requests welcome.
