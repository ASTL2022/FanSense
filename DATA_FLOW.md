# FanSense 数据流程

> 2026-07-19 · 全代码审查后梳理

---

## 概览

```
┌─────────────────────────────────────────────────────────┐
│                    主循环 (1s Tick)                       │
│  dataTimer ──► refresh() ──► Task.detached ──► UI 更新   │
│  bgSampleTimer (63s) ──► 功耗采样 + 告警                  │
└─────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         runHelper()      IOKit/Darwin     sysctl/host_stat
         (fanhelper)      直接读取         直接读取
```

---

## 1. SMC 风扇数据流

```
dataTimer (1s)
  │
  ▼
refresh()
  │ 读取 needFans = hasHelper && (isOpen || tick % 10 == 0)
  ▼
Task.detached ──► runHelper(["all"] or ["read"])
  │                 │
  │                 ▼
  │               Process ──► /usr/local/bin/fanhelper
  │                              │
  │                              ▼ smc_open() → SMC kernel
  │                              │ F0Ac/F0Mn/F0Mx/F0Tg/F0Md
  │                              ▼ stdout: "0 cur=2000 min=1500..."
  │
  ▼ parseFans(stdout) → [FanState]
  │   { cur, min, max, target, mode }
  │
  ▼ MainActor.run ──► avgRPM = Σcur / count
  │                   smcManual = any(mode == 1)
  │                   fanMode sync (writeInFlight guard)
  │
  ├─► FanView.update(cur, min, max, target, mode, smcManual)
  │     ├─ slider 同步 (auto→min, else→cur)
  │     ├─ RPM 数字 + 模式标签 + 目标RPM
  │     └─ 60s 历史曲线 (Catmull-Rom 样条, 颜色分段)
  │
  └─► updateIconRotation() → iconModel.spinning = avgRPM >= 100
```

## 2. 传感器/温度数据流

```
refresh() → runHelper(["all"])
  │
  │ stdout 分段: "---\n"
  │   前半 = 风扇 (→ §1)
  │   后半 = 传感器
  ▼
parseSensors(stdout)
  │  cpu_temp, gpu_temp, battery_temp, pstr, pdtr
  │  battery_remaining, battery_capacity, battery_voltage
  ▼
MainActor.run
  │
  └─► TempBarView   (CPU/GPU/电池温度, warnAt 60/95°C)
```

```
bgSampleTimer (63s, 偏移避免碰撞)
  │  runHelper(["sensors"]) → parseSensors()
  ▼
MainActor.run
  ├─ lastSensorData = s, lastSensorTime = Date()
  ├─ powerSamples 累积 (不在缓冲期内)
  ├─ efficiencyView.avgWatts / timeToEmpty / isOnBattery
  └─ checkPowerAlert() → !lastIsOnAC && samples==5 && avg≥15W && tte<3min
```

## 3. CPU / 内存 / GPU 数据流 (同步)

```
refresh() ──► MainActor (同步调用, 无 Process)
  │
  ├─ readCPU(&prevCPUTicks)
  │    host_statistics64 → cpu_ticks → 差分 → percent (user+sys)
  │    → MetricBarView "CPU"
  │
  ├─ readMemory()
  │    host_statistics64 + vm_statistics64 → usedGB/percent
  │    sysctlbyname("vm.swapusage") → swapUsedGB
  │    → MetricBarView "内存"
  │
  └─ readGPUUtilization()  (在 MainActor.run 内调用)
       IOServiceMatching("AGXAccelerator*") → PerformanceStatistics
       → MetricBarView "GPU"
```

## 4. 网络数据流 (同步)

```
refresh() → readNetwork(&prevNetBytes)
  │
  getifaddrs() → 遍历 en*/utun* 接口 → 求和 totalRx/totalTx
  │  (改前: 只取最大单接口, 改后: 多接口合计)
  │
  │ CACurrentMediaTime() → dt 差分 → rxBytesPerSec / txBytesPerSec
  ▼
NetBarView "下载/上传"
```

## 5. 磁盘数据流

```
refresh(slow: true) 每 30s
  │
  ├─ readDisk()
  │    URL.resourceValues(.volumeAvailableCapacityForImportantUsage)
  │    → usedGB / totalGB → percent
  │    → diskBarView "已用"
  │
  └─ smartInfo (启动时 readSmartOnce(), 仅一次)
       runHelper(["smart"]) → fanhelper → nvme_smart.c
         IONVMeSMARTUserClient → SMART log page 02h
       parseSmart() → health%, spare%, writtenTB, temp
       → diskBarView "健康"
```

## 6. 电池数据流

```
refresh() → readBatteryPS()  (isOpen || isChargingMode)
  │
  ├─ IOPSCopyPowerSourcesInfo → percent, isCharging, isOnAC
  │    timeToEmpty / timeToFull
  │
  ├─ IOServiceGetMatchingService("AppleSmartBattery")
  │    → cycleCount, maxCapacity, designCapacity, healthPercent
  │    → adapterWatts
  │
  └─ SMC 传感器 (parseSensors)
       battery_remaining + battery_current → estimateTimeToEmpty()
       (只在 IOPowerSources timeToEmpty ≤ 0 时作为降级)
  │
  ▼ BatteryBarView + EfficiencyView
     ├─ 缓冲期 (拔电 25s): "⚡ 正在计算续航…"
     ├─ 放电模式:  "剩余续航 XhXm · X.XW"
     ├─ 充电模式:  "X.XW"
     └─ 满电/AC:   "健康 X% · N 次循环"
```

## 7. 系统信息数据流

```
refresh(slow: true) 每 30s
  │
  └─ readSystemHeader()
       ├─ sysctlbyname("hw.model") → 硬件型号
       ├─ IORegistryEntryCreateCFProperty("model") → 商品名
       ├─ sysctlbyname("kern.boottime") → uptime 计算
       └─ ProcessInfo.operatingSystemVersion → macOS X.Y
  │
  ▼ HeaderView "MacBook Pro, 已运行 X天Y小时"
```

## 8. 风扇控制写路径 (用户交互 → SMC)

```
                    ┌─ sliderMoved ──► pendingChange=true
                    │  debounce 0.2s
                    │    │
                    │    ├─ rpm ≤ min+1 ──► restoreAutoMode()
                    │    │                     │ bump gen
                    │    │                     ▼ runHelper(["auto"])
                    │    │
                    │    └─ rpm > min+1 ──► bump gen, fanMode=.manual
                    │                         ▼ Task.detached
                    │                         runHelper(["set","N"]) ×3 retries
                    │                         (per-attempt gen check)
                    │
 toggleChargingMode ─┤  (右键菜单)
                    │  bump gen, fanMode=.charging
                    ▼  Task.detached
                       runHelper(["read"]) → max RPM
                       runHelper(["set","max"]) ×3 retries
                       (per-attempt gen check)
```

```
fanhelper 写路径:
  clamp_and_set(rpm) ──► 读 F0Mn/F0Mx → clamp → F0Md=1, F0Tg=rpm
  set_auto()        ──► F0Md=0 (所有风扇)
  smc kernel call   ──► IOConnectCallStructMethod(AppleSMC)
```

## 9. 面板生命周期

```
left-click statusItem
  └─► togglePanel() → showPanel()
        ├─ setFrameOrigin(按钮下方)
        ├─ makeKeyAndOrderFront
        ├─ addGlobalMonitorForEvents (点击面板外 → hidePanel)
        └─ refresh(slow: true, force: true)

right-click / ctrl+click statusItem
  └─► showContextMenu()
        ├─ "充电模式" toggle → toggleChargingMode()
        └─ "退出" → quit() → runHelper(["auto"]) → terminate

globalMonitor 触发
  └─► hidePanel() → orderOut + removeMonitor
```

## 10. 状态同步规则

```
refresh() → MainActor.run
  │
  │ smcManual = fans.contains(mode == 1)
  │
  ├─ writeInFlight > 0  ──► 跳过, 等写完成
  ├─ fanView.pendingChange  ──► 跳过, 等用户操作完成
  │
  └─ writeInFlight == 0 && !pendingChange:
       ├─ !smcManual && fanMode != .auto  ──► fanMode = .auto
       └─ smcManual && fanMode == .auto   ──► fanMode = .manual (反失同步)
```

## 11. 保护机制

| 机制 | 说明 |
|------|------|
| refreshInFlight | 防止并发 refresh 冲刷 SMC (间隔<1s 跳过) |
| writeInFlight | 标记进行中的 SMC 写, 防 sync 规则误触 |
| pendingChange | 标记用户拖拽中, 防 SMC 回读覆写 UI |
| setGeneration | 命令版本号, 超时的旧任务自动中止 |
| helperVersion | 启动时校验 /usr/local/bin/fanhelper 版本, 不匹配提示重装 |
| runHelper 5s 超时 | Process 超时自动 kill, 避免卡死 |
| powerTransitionUntil | 拔电后 25s 缓冲, 避免瞬态功率异常 |
| lastSensorTime | 传感器数据时间戳，功耗采样依赖 |
