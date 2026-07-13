import Foundation

@discardableResult
func runHelper(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: HELPER_PATH)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func parseFans(_ raw: String) -> [FanState] {
    var fans: [FanState] = []
    for line in raw.split(separator: "\n") {
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

func parseSensors(_ raw: String) -> SensorData {
    var s = SensorData()
    for line in raw.split(separator: "\n") {
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
            if let raw = Int(val) { s.batteryCurrent = Int(Int16(truncatingIfNeeded: raw)) }
        case "pstr": s.pstr = Double(val) ?? 0
        case "pdtr": s.pdtr = Double(val) ?? 0
        default: break
        }
    }
    return s
}
