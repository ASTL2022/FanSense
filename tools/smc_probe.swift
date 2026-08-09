// SPDX-License-Identifier: GPL-3.0-or-later
// 最小探针：验证非 root 进程内直接读 SMC 风扇/温度是否可行

import Foundation

func readFloat(_ key: String) -> Float {
    var v: Float = 0
    key.withCString { smc_read_float($0, &v) }
    return v
}

func readInt(_ key: String) -> Int32 {
    var v: Int32 = 0
    key.withCString { smc_read_int($0, &v) }
    return v
}

let rc = smc_open()
guard rc == 0 else {
    print("smc_open failed: \(rc)")
    exit(1)
}
defer { smc_close() }

let fanCount = readInt("FNum")
print("fan_count=\(fanCount)")
for i in 0..<fanCount {
    let cur    = readFloat(String(format: "F%dAc", i))
    let min    = readFloat(String(format: "F%dMn", i))
    let max    = readFloat(String(format: "F%dMx", i))
    let target = readFloat(String(format: "F%dTg", i))
    let mode   = readInt(String(format: "F%dMd", i))
    print(String(format: "fan%d cur=%.0f min=%.0f max=%.0f target=%.0f mode=%d",
                 i, cur, min, max, target, mode))
}

let cpuKeys = [
    "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H",
    "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    "Te05", "Te09", "Te0H", "Te0S", "Te0L", "Te0P",
]
let gpuKeys = [
    "Tg0D", "Tg05", "Tg0L", "Tg0T", "Tg0f", "Tg0n",
    "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
    "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0j", "Tg0k",
]
let battKeys = ["TB0T", "TB1T", "TB2T"]

func avg(_ keys: [String]) -> Float {
    var sum: Float = 0
    var count = 0
    for k in keys {
        let v = readFloat(k)
        if v > 0 { sum += v; count += 1 }
    }
    return count > 0 ? sum / Float(count) : 0
}

print(String(format: "cpu_temp=%.1f", avg(cpuKeys)))
print(String(format: "gpu_temp=%.1f", avg(gpuKeys)))
print(String(format: "battery_temp=%.1f", avg(battKeys)))
print(String(format: "pstr=%.2f", readFloat("PSTR")))
print(String(format: "pdtr=%.2f", readFloat("PDTR")))
print("uid=\(getuid()) euid=\(geteuid())")
