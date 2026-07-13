import Foundation
import IOKit
import IOKit.ps
import Darwin
import QuartzCore

// MARK: - CPU

func readCPU(_ prev: inout (user: UInt64, sys: UInt64, idle: UInt64)) -> CPUInfo {
    var info = CPUInfo()
    var cpuLoad = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &cpuLoad) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return info }

    let curUser = UInt64(cpuLoad.cpu_ticks.0)
    let curSys  = UInt64(cpuLoad.cpu_ticks.1)
    let curIdle = UInt64(cpuLoad.cpu_ticks.2)

    let firstCall = prev == (0, 0, 0)
    let du = curUser &- prev.user
    let ds = curSys  &- prev.sys
    let di = curIdle &- prev.idle
    let total = Double(du + ds + di)

    prev = (curUser, curSys, curIdle)
    if !firstCall && total > 0 {
        info.user = Double(du) / total
        info.system = Double(ds) / total
        info.idle = Double(di) / total
        info.percent = info.user + info.system
    }
    return info
}

// MARK: - GPU

func readGPUUtil() -> Double {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("AGXAcceleratorG13X"), &iter) == KERN_SUCCESS, iter != 0
    else { return -1 }
    let svc = IOIteratorNext(iter)
    IOObjectRelease(iter)
    guard svc != 0 else { return -1 }
    defer { IOObjectRelease(svc) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let ps = dict["PerformanceStatistics"] as? [String: Any],
          let dev = ps["Device Utilization %"] as? Int
    else { return -1 }
    return Double(dev) / 100.0
}

// MARK: - Memory

func readMemory() -> MemoryInfo {
    var info = MemoryInfo()
    let pageSize = Double(vm_page_size)
    let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
    info.totalGB = totalBytes / 1e9

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return info }

    let wiredBytes      = Double(stats.wire_count) * pageSize
    let activeBytes     = Double(stats.active_count) * pageSize
    let compressedBytes = Double(stats.compressor_page_count) * pageSize

    info.wiredGB      = wiredBytes / 1e9
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

// MARK: - Network

func readNetwork(_ prev: inout (rx: UInt64, tx: UInt64, time: Double)) -> NetworkInfo {
    var info = NetworkInfo()
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return info }
    defer { freeifaddrs(first) }

    var best: (name: String, rx: UInt64, tx: UInt64) = ("", 0, 0)
    var ptr = first
    while true {
        let name = String(cString: ptr.pointee.ifa_name)
        let isTarget = name.hasPrefix("en") || name.hasPrefix("utun")
        if isTarget, ptr.pointee.ifa_addr != nil,
           ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
           let dataPtr = ptr.pointee.ifa_data {
            let data = dataPtr.bindMemory(to: if_data.self, capacity: 1)
            let rx = UInt64(data.pointee.ifi_ibytes)
            let tx = UInt64(data.pointee.ifi_obytes)
            if rx + tx > best.rx + best.tx { best = (name, rx, tx) }
        }
        guard let next = ptr.pointee.ifa_next else { break }
        ptr = next
    }

    let rx = best.rx; let tx = best.tx
    let now = CACurrentMediaTime()
    let dt  = now - prev.time
    if prev.time > 0 && dt > 0 && rx >= prev.rx && tx >= prev.tx {
        info.rxBytesPerSec = Double(rx - prev.rx) / dt
        info.txBytesPerSec = Double(tx - prev.tx) / dt
    }
    prev = (rx, tx, now)
    return info
}

// MARK: - Disk

func readDisk() -> DiskInfo {
    var info = DiskInfo()
    guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
          let total = attrs[.systemSize]     as? Int64,
          let free  = attrs[.systemFreeSize] as? Int64
    else { return info }
    info.totalGB = Double(total) / 1e9
    info.usedGB  = Double(total - free) / 1e9
    info.percent = info.totalGB > 0 ? info.usedGB / info.totalGB : 0
    return info
}

// MARK: - Battery (IOPowerSources)

func readBattery() -> BatteryInfo {
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
            info.percent     = max > 0 ? Double(cur) / Double(max) : 0
            info.isCharging  = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state        = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            info.isOnAC      = (state == kIOPSACPowerValue)
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
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any]
    else { return info }

    if let adapter = dict["AdapterDetails"] as? [String: Any] {
        info.adapterWatts = adapter["Watts"] as? Int ?? 0
    }
    info.designCapacity = (dict["BatteryData"] as? [String: Any])?["DesignCapacity"] as? Int
                       ?? dict["DesignCapacity"] as? Int ?? 0
    info.maxCapacity    = (dict["BatteryData"] as? [String: Any])?["FullChargeCapacity"] as? Int
                       ?? dict["FullChargeCapacity"] as? Int ?? 0
    info.cycleCount     = dict["CycleCount"] as? Int ?? 0
    if info.timeToEmpty <= 0 { info.timeToEmpty = dict["TimeRemaining"] as? Int ?? -1 }
    if info.timeToFull  <= 0 { info.timeToFull  = dict["AvgTimeToFull"] as? Int ?? -1 }
    if info.designCapacity > 0 { info.healthPercent = Double(info.maxCapacity) / Double(info.designCapacity) }
    return info
}

// MARK: - System Header

func readSystemHeader() -> SystemHeader {
    var h = SystemHeader()
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    h.osVersion = "macOS \(ver.majorVersion).\(ver.minorVersion)"

    var tv = timeval()
    var sz = size_t(MemoryLayout<timeval>.size)
    if sysctlbyname("kern.boottime", &tv, &sz, nil, 0) == 0 {
        let secs = Int(Date().timeIntervalSince1970) - Int(tv.tv_sec)
        let d = secs / 86400, hr = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0      { h.uptime = "已运行 \(d)天\(hr)小时" }
        else if hr > 0 { h.uptime = "已运行 \(hr)小时\(m)分" }
        else          { h.uptime = "已运行 \(m)分钟" }
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
                h.modelName = name
            } else { h.modelName = hwModel }
            IOObjectRelease(platformSvc)
        } else { h.modelName = hwModel }
    } else { h.modelName = "Mac" }

    var chipBuf = [CChar](repeating: 0, count: 256)
    var chipSz  = size_t(chipBuf.count)
    if sysctlbyname("machdep.cpu.brand_string", &chipBuf, &chipSz, nil, 0) == 0 {
        h.chip = String(cString: chipBuf)
    }
    return h
}

// MARK: - Formatting

func formatBytes(_ b: Double) -> String {
    if b >= 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
    if b >= 1_000     { return String(format: "%.0f KB/s", b / 1_000) }
    return "0 KB/s"
}
