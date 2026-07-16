// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

import Foundation
import IOKit
import IOKit.ps
import Darwin
import QuartzCore

let HELPER    = "/usr/local/bin/fanhelper"

// MARK: - Data Models

struct FanState {
    var cur = 0.0, min = 0.0, max = 6000.0, target = 0.0, mode = 0
}

struct SensorData {
    var cpuTemp: Double = 0
    var gpuTemp: Double = 0
    var batteryTemp: Double = 0
    var batteryRemaining: Int = 0
    var batteryCapacity: Int = 0
    var batteryVoltage: Int = 0
    var batteryCurrent: Int = 0   // signed mA: >0 charging, <0 discharging (raw SMC, noisy)
    var pstr: Double = 0          // System Total Rail — whole-system power, live on AC+battery
    var pdtr: Double = 0          // DC In Total Rail  — adapter input, ~0 on battery
}

// MARK: - Helper Process

@discardableResult
func runHelper(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: HELPER)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func parseFans(_ out: String) -> [FanState] {
    var fans: [FanState] = []
    for line in out.split(separator: "\n") {
        let parts = line.split(separator: " ")
        guard let first = parts.first, Int(first) != nil else { continue }
        var f = FanState()
        for kv in parts.dropFirst() {
            let pair = kv.split(separator: "=")
            guard pair.count == 2, let v = Double(pair[1]) else { continue }
            switch pair[0] {
            case "cur":    f.cur    = v
            case "min":    f.min    = v
            case "max":    f.max    = v
            case "target": f.target = v
            case "mode":   f.mode   = Int(v)
            default: break
            }
        }
        fans.append(f)
    }
    return fans
}

func parseSensors(_ out: String) -> SensorData {
    var s = SensorData()
    for line in out.split(separator: "\n") {
        let pair = line.split(separator: "=")
        guard pair.count == 2 else { continue }
        let key = String(pair[0])
        let val = String(pair[1])
        switch key {
        case "cpu_temp":          s.cpuTemp          = Double(val) ?? 0
        case "gpu_temp":          s.gpuTemp          = Double(val) ?? 0
        case "battery_temp":      s.batteryTemp      = Double(val) ?? 0
        case "battery_remaining": s.batteryRemaining = Int(val) ?? 0
        case "battery_capacity":  s.batteryCapacity  = Int(val) ?? 0
        case "battery_voltage":   s.batteryVoltage   = Int(val) ?? 0
        case "battery_current":
            if let raw = Int(val) {
                s.batteryCurrent = Int(Int16(truncatingIfNeeded: raw))
            }
        case "pstr": s.pstr = Double(val) ?? 0
        case "pdtr": s.pdtr = Double(val) ?? 0
        default: break
        }
    }
    return s
}

// MARK: - System Stats

struct SmartInfo {
    var ok: Bool = false
    var health: Int = 0        // 100 - percentage_used
    var spare: Int = 0         // available spare %
    var writtenTB: Double = 0
    var temp: Int = 0
}

func parseSmart(_ out: String) -> SmartInfo {
    var s = SmartInfo()
    for line in out.split(separator: "\n") {
        let pair = line.split(separator: "=")
        guard pair.count == 2 else { continue }
        let key = String(pair[0])
        let val = String(pair[1])
        switch key {
        case "smart_ok":         s.ok        = val == "1"
        case "smart_health":     s.health    = Int(val) ?? 0
        case "smart_spare":      s.spare     = Int(val) ?? 0
        case "smart_written_tb": s.writtenTB = Double(val) ?? 0
        case "smart_temp":       s.temp      = Int(val) ?? 0
        default: break
        }
    }
    return s
}

struct MemoryInfo {
    var usedGB: Double = 0
    var totalGB: Double = 0
    var wiredGB: Double = 0
    var compressedGB: Double = 0
    var swapUsedGB: Double = 0
    var percent: Double = 0     // used / total
    var pressure: Double = 0    // 0-1 (wired+compressed / total)
}

func readMemory() -> MemoryInfo {
    var info = MemoryInfo()
    let pageSize = Double(vm_page_size)
    let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
    info.totalGB = totalBytes / 1e9

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return info }

    let wiredBytes      = Double(stats.wire_count)            * pageSize
    let activeBytes     = Double(stats.active_count)          * pageSize
    let compressedBytes = Double(stats.compressor_page_count) * pageSize

    info.wiredGB      = wiredBytes      / 1e9
    info.compressedGB = compressedBytes / 1e9
    info.usedGB       = (wiredBytes + activeBytes + compressedBytes) / 1e9
    info.percent      = min(info.usedGB / info.totalGB, 1.0)
    info.pressure     = min((wiredBytes + compressedBytes) / totalBytes, 1.0)

    var swapInfo = xsw_usage()
    var swapSize = size_t(MemoryLayout<xsw_usage>.size)
    if sysctlbyname("vm.swapusage", &swapInfo, &swapSize, nil, 0) == 0 {
        info.swapUsedGB = Double(swapInfo.xsu_used) / 1e9
    }
    return info
}

struct CPUInfo {
    var percent: Double = 0    // user + sys, 0-1
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
}

func readCPU(prevTicks: inout (user: UInt64, sys: UInt64, idle: UInt64)) -> CPUInfo {
    var info = CPUInfo()
    var cpuLoad = host_cpu_load_info()
    var count   = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result  = withUnsafeMutablePointer(to: &cpuLoad) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return info }

    let curUser = UInt64(cpuLoad.cpu_ticks.0)
    let curSys  = UInt64(cpuLoad.cpu_ticks.1)
    let curIdle = UInt64(cpuLoad.cpu_ticks.2)

    let firstCall = prevTicks == (0, 0, 0)
    let du = curUser &- prevTicks.user
    let ds = curSys  &- prevTicks.sys
    let di = curIdle &- prevTicks.idle
    let total = Double(du + ds + di)

    prevTicks = (curUser, curSys, curIdle)

    if !firstCall && total > 0 {
        info.user   = Double(du) / total
        info.system = Double(ds) / total
        info.idle   = Double(di) / total
        info.percent = info.user + info.system
    }
    return info
}

struct NetworkInfo {
    var rxBytesPerSec: Double = 0
    var txBytesPerSec: Double = 0
}

func readNetwork(interface: String = "", prevBytes: inout (rx: UInt64, tx: UInt64, time: Double)) -> NetworkInfo {
    var info = NetworkInfo()
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return info }
    defer { freeifaddrs(first) }

    var best: (name: String, rx: UInt64, tx: UInt64) = ("", 0, 0)
    var ptr = first
    while true {
        let name = String(cString: ptr.pointee.ifa_name)
        let isTarget = interface.isEmpty
            ? (name.hasPrefix("en") || name.hasPrefix("utun"))
            : name == interface
        if isTarget, ptr.pointee.ifa_addr != nil,
           ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
           let dataPtr = ptr.pointee.ifa_data {
            let data = dataPtr.bindMemory(to: if_data.self, capacity: 1)
            let rx = UInt64(data.pointee.ifi_ibytes)
            let tx = UInt64(data.pointee.ifi_obytes)
            if rx + tx > best.rx + best.tx {
                best = (name, rx, tx)
            }
        }
        guard let next = ptr.pointee.ifa_next else { break }
        ptr = next
    }

    let rx = best.rx
    let tx = best.tx
    let now = CACurrentMediaTime()
    let dt  = now - prevBytes.time
    if prevBytes.time > 0 && dt > 0 && rx >= prevBytes.rx && tx >= prevBytes.tx {
        info.rxBytesPerSec = Double(rx - prevBytes.rx) / dt
        info.txBytesPerSec = Double(tx - prevBytes.tx) / dt
    }
    prevBytes = (rx, tx, now)
    return info
}

func readGPUUtilization() -> Double {
    let gpuModels = [
        "AGXAcceleratorG16X", "AGXAcceleratorG15X", "AGXAcceleratorG14X",
        "AGXAcceleratorG13X", "AGXAccelerator"
    ]
    for model in gpuModels {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                IOServiceMatching(model), &iter) == KERN_SUCCESS,
            iter != 0 else { continue }
        let svc = IOIteratorNext(iter)
        IOObjectRelease(iter)
        guard svc != 0 else { continue }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let ps = dict["PerformanceStatistics"] as? [String: Any],
              let dev = ps["Device Utilization %"] as? Int
        else { continue }
        return Double(dev) / 100.0
    }
    return -1
}

struct DiskInfo {
    var usedGB: Double = 0
    var totalGB: Double = 0
    var percent: Double = 0
}

func readDisk(path: String = "/") -> DiskInfo {
    var info = DiskInfo()
    // importantUsage 口径包含可清除空间（快照/缓存），与系统设置显示一致
    let url = URL(fileURLWithPath: path)
    if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
       let total = v.volumeTotalCapacity, total > 0,
       let avail = v.volumeAvailableCapacityForImportantUsage, avail > 0 {
        info.totalGB = Double(total) / 1e9
        info.usedGB  = Double(Int64(total) - avail) / 1e9
        info.percent = info.usedGB / info.totalGB
    return info
}

// MARK: - Battery Time Estimation

func estimateTimeToEmpty(from s: SensorData) -> Int {
    guard s.batteryRemaining > 0, s.batteryCurrent < 0 else { return -1 }
    return Int(Double(s.batteryRemaining) / Double(-s.batteryCurrent) * 60.0)
}

func effectiveTimeToEmpty(bat: BatteryInfo?, sensors: SensorData) -> Int {
    if let tte = bat?.timeToEmpty, tte > 0 { return tte }
    return estimateTimeToEmpty(from: sensors)
}
    guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
          let total = attrs[.systemSize]         as? Int64,
          let free  = attrs[.systemFreeSize]     as? Int64
    else { return info }
    info.totalGB = Double(total) / 1e9
    info.usedGB  = Double(total - free) / 1e9
    info.percent = info.totalGB > 0 ? info.usedGB / info.totalGB : 0
    return info
}

func formatBytes(_ b: Double) -> String {
    if b >= 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
    if b >= 1_000     { return String(format: "%.0f KB/s", b / 1_000) }
    return "0 KB/s"
}

struct SystemHeaderInfo {
    var modelName: String = ""
    var chip: String = ""
    var osVersion: String = ""
    var uptimeStr: String = ""
}

func readSystemHeader() -> SystemHeaderInfo {
    var info = SystemHeaderInfo()

    let ver = ProcessInfo.processInfo.operatingSystemVersion
    info.osVersion = "macOS \(ver.majorVersion).\(ver.minorVersion)"

    var tv = timeval()
    var sz = size_t(MemoryLayout<timeval>.size)
    if sysctlbyname("kern.boottime", &tv, &sz, nil, 0) == 0 {
        let secs = Int(Date().timeIntervalSince1970) - Int(tv.tv_sec)
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        if d > 0      { info.uptimeStr = "已运行 \(d)天\(h)小时" }
        else if h > 0 { info.uptimeStr = "已运行 \(h)小时\(m)分" }
        else          { info.uptimeStr = "已运行 \(m)分钟" }
    }

    var modelBuf = [CChar](repeating: 0, count: 256)
    var modelSz  = size_t(modelBuf.count)
    if sysctlbyname("hw.model", &modelBuf, &modelSz, nil, 0) == 0 {
        let hwModel = String(cString: modelBuf)
        let platformSvc = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice"))
        if platformSvc != 0 {
            if let raw = IORegistryEntryCreateCFProperty(platformSvc,
                    "model" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Data,
               let name = String(data: raw.filter({ $0 != 0 }), encoding: .utf8) {
                info.modelName = name
            } else {
                info.modelName = hwModel
            }
            IOObjectRelease(platformSvc)
        } else {
            info.modelName = hwModel
        }
    } else {
        info.modelName = "Mac"
    }
    var chipBuf = [CChar](repeating: 0, count: 256)
    var chipSz  = size_t(chipBuf.count)
    if sysctlbyname("machdep.cpu.brand_string", &chipBuf, &chipSz, nil, 0) == 0 {
        info.chip = String(cString: chipBuf)
    }
    return info
}

// MARK: - IOPowerSources battery info

struct BatteryInfo {
    var hasBattery: Bool = false
    var percent: Double = 0        // 0.0 – 1.0
    var isCharging: Bool = false
    var isOnAC: Bool = false
    var timeToEmpty: Int = -1
    var timeToFull: Int = -1
    var adapterWatts: Int = 0
    var cycleCount: Int = 0
    var designCapacity: Int = 0
    var maxCapacity: Int = 0
    var healthPercent: Double = 0
}

func readBatteryPS() -> BatteryInfo {
    var info = BatteryInfo()

    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
        for src in list {
            guard let rawDesc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue(),
                  let desc = rawDesc as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            info.hasBattery = true
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey]     as? Int ?? 100
            info.percent    = max > 0 ? Double(cur) / Double(max) : 0
            info.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state       = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            info.isOnAC     = (state == kIOPSACPowerValue)
            info.timeToEmpty = desc[kIOPSTimeToEmptyKey]      as? Int ?? -1
            info.timeToFull  = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            break
        }
    }

    guard info.hasBattery else { return info }

    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                      IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return info }
    defer { IOObjectRelease(service) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props,
              kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any]
    else { return info }

    if let adapter = dict["AdapterDetails"] as? [String: Any] {
        info.adapterWatts = adapter["Watts"] as? Int ?? 0
    }

    if let batData = dict["BatteryData"] as? [String: Any] {
        info.designCapacity = batData["DesignCapacity"] as? Int ?? 0
        info.maxCapacity    = batData["FullChargeCapacity"] as? Int ?? 0
    } else {
        info.designCapacity = dict["DesignCapacity"] as? Int ?? 0
        info.maxCapacity    = dict["FullChargeCapacity"] as? Int ?? 0
    }
    info.cycleCount = dict["CycleCount"] as? Int ?? 0
    if info.timeToEmpty <= 0 {
        info.timeToEmpty = dict["TimeRemaining"] as? Int ?? -1
    }
    if info.timeToFull <= 0 {
        info.timeToFull = dict["AvgTimeToFull"] as? Int ?? -1
    }
    if info.designCapacity > 0 {
        info.healthPercent = Double(info.maxCapacity) / Double(info.designCapacity)
    }

    return info
}

// MARK: - Battery Time Estimation

func estimateTimeToEmpty(from s: SensorData) -> Int {
    guard s.batteryRemaining > 0, s.batteryCurrent < 0 else { return -1 }
    return Int(Double(s.batteryRemaining) / Double(-s.batteryCurrent) * 60.0)
}

func effectiveTimeToEmpty(bat: BatteryInfo?, sensors: SensorData) -> Int {
    if let tte = bat?.timeToEmpty, tte > 0 { return tte }
    return estimateTimeToEmpty(from: sensors)
}
