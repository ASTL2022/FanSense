# FanSense 数据流程

> 2026-08-09 · 与 v1.4.1 实际代码对齐

---

## 概览

```
┌───────────────────────────────────────────────────────────┐
│        主循环 (1s 面板开 / 120s 面板关)                     │
│  dataTimer ──► refresh() ──► Task.detached ──► UI 更新    │
│  bgSampleTimer (60s, 偏移3s) ──► 电池/功耗采样 + 告警      │
└───────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         SMC 进程内直读    IOKit/IOPower     sysctl/host_stat
         (smcMonitor)      直接读取          直接读取
```

---

## 1. SMC 风扇数据流

```
dataTimer (1s 面板开 / 120s 面板关)
  │
  ▼
refresh()
  │
  ▼
Task.detached ──► smcMonitor（actor，进程内直读 SMC）
  │                 ├─ 面板开: readAll()  → 风扇键 + 传感器键
  │                 └─ 面板关: readFans()  → 仅风扇键，温度/功耗键不读
  ▼
[FanState] { cur, min, max, target, mode }
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
refresh() → Task.detached → smcMonitor.readAll()
  │  （仅面板打开时读取；关闭时跳过温度/功耗键）
  ▼
SensorData { cpuTemp, gpuTemp, batteryTemp, pstr, pdtr,
             battery_remaining, battery_capacity, battery_voltage }
  ▼
MainActor.run
  │
  └─► TempBarView   (CPU/GPU/电池温度, warnAt 60/95°C)
```

```
bgSampleTimer (60s, 偏移 3s)
  │  readBatteryPS() +（电池供电时）smcMonitor.readSensors()
  ▼
MainActor.run
  ├─ lastSensorData = s, lastSensorTime = Date()
  ├─ powerSamples 累积 (不在缓冲期内)
  ├─ efficiencyView.avgWatts / timeToEmpty / isOnBattery
  └─ checkPowerAlert() → !lastIsOnAC && samples==5 && avg≥15W && tte<3min
```

## 3. CPU / 内存 / GPU 数据流

```
refresh()
  │
  ├─ readCPU(&prevCPUTicks)        主线程同步（快）
  │    host_statistics64 → cpu_ticks → 差分 → percent (user+sys)
  │    → MetricBarView "CPU"
  │
  ├─ readMemory()                  Task.detached 后台执行
  │    host_statistics64 + vm_statistics64 → usedGB/percent
  │    sysctlbyname("vm.swapusage") → swapUsedGB
  │    → MetricBarView "内存"
  │
  └─ readGPUUtilization()          MainActor.run 内调用，2s 节流
       IOServiceMatching("AGXAccelerator*") → PerformanceStatistics
       → MetricBarView "GPU"
```

## 4. 网络数据流 (同步)

```
refresh() → readNetwork(&prevNetBytes)  (主线程同步)
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
refresh() → readBatteryThrottled()  (面板打开时, 5s 节流)
PowerAlertService → readBatteryPS() （后台每 60s 独立采样）
  │
  ├─ IOPSCopyPowerSourcesInfo → percent, isCharging, isOnAC
  │    timeToEmpty / timeToFull
  │
  ├─ IOServiceGetMatchingService("AppleSmartBattery")
  │    → cycleCount, maxCapacity, designCapacity, healthPercent
  │    → adapterWatts
  │
  └─ SMC 传感器 (smcMonitor.readAll())
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
        └─ refresh(slow: true)

right-click / ctrl+click statusItem
  └─► showContextMenu()
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
| refreshInFlight | 防止并发 refresh 重复采样；force 调用可绕过（风扇写完成/面板打开时立即刷新）|
| writeInFlight | 标记进行中的 SMC 写, 防 sync 规则误触 |
| pendingChange | 标记用户拖拽中, 防 SMC 回读覆写 UI |
| setGeneration | 命令版本号, 超时的旧任务自动中止 |
| helperVersion | 启动时校验 /usr/local/bin/fanhelper 版本, 不匹配提示重装 |
| runHelper 5s 超时 | Process 超时自动 kill, 避免卡死 |
| powerTransitionUntil | 拔电后 25s 缓冲, 避免瞬态功率异常 |
| lastSensorTime | 传感器数据时间戳，功耗采样依赖 |
