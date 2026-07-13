import Cocoa

let HELPER_PATH = "/usr/local/bin/fanhelper"

struct FanState {
    var cur: Double = 0
    var min: Double = 0
    var max: Double = 6000
    var target: Double = 0
    var mode: Int = 0
}

struct SensorData {
    var cpuTemp: Double = 0
    var gpuTemp: Double = 0
    var batteryTemp: Double = 0
    var batteryRemaining: Int = 0
    var batteryCapacity: Int = 0
    var batteryVoltage: Int = 0
    var batteryCurrent: Int = 0
    var pstr: Double = 0
    var pdtr: Double = 0
}

struct BatteryInfo {
    var hasBattery: Bool = false
    var percent: Double = 0
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

struct MemoryInfo {
    var usedGB: Double = 0
    var totalGB: Double = 0
    var wiredGB: Double = 0
    var compressedGB: Double = 0
    var swapUsedGB: Double = 0
    var percent: Double = 0
    var pressure: Double = 0
}

struct CPUInfo {
    var percent: Double = 0
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
}

struct NetworkInfo {
    var rxBytesPerSec: Double = 0
    var txBytesPerSec: Double = 0
}

struct DiskInfo {
    var usedGB: Double = 0
    var totalGB: Double = 0
    var percent: Double = 0
}

struct SystemHeader {
    var modelName: String = ""
    var chip: String = ""
    var osVersion: String = ""
    var uptime: String = ""
}

// MARK: - Design Tokens

enum Layout {
    static let panelWidth: CGFloat   = 560
    static let cardRadius: CGFloat   = 14
    static let panelRadius: CGFloat  = 18
    static let cardHPad: CGFloat     = 8
    static let colGap: CGFloat       = 8
    static let cardGap: CGFloat      = 10
    static let innerPad: CGFloat     = 16
    static let barHeight: CGFloat    = 5
    static let barRadius: CGFloat    = 2.5
    static let sectionHeadH: CGFloat = 16
    static let rowHeight: CGFloat    = 56
    static let rowGap: CGFloat       = 8
}

enum Typography {
    static let bigValue  = { NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold) }
    static let hugeValue = { NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold) }
    static let label     = { NSFont.systemFont(ofSize: 10, weight: .regular) }
    static let section   = { NSFont.systemFont(ofSize: 9, weight: .regular) }
    static let state     = { NSFont.systemFont(ofSize: 22, weight: .semibold) }
}
