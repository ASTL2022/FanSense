import Foundation
import IOKit

// IOReport private API via dlopen
let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)

typealias IOReportCopyChannelsFn = @convention(c) (CFDictionary?, CFDictionary?) -> Unmanaged<CFArray>?
typealias IOReportCopyAllChannelsFn = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
typealias IOReportCreateSubscriptionFn = @convention(c) (CFAllocator?, CFDictionary, UnsafeMutablePointer<CFMutableDictionary?>?, UInt64, CFDictionary?) -> Unmanaged<AnyObject>?
typealias IOReportCreateSamplesFn = @convention(c) (AnyObject, CFMutableDictionary, CFDictionary?) -> Unmanaged<CFArray>?

let _copyAll   = dlsym(handle, "IOReportCopyAllChannels")
let _copyChan  = dlsym(handle, "IOReportCopyChannelsWithID")

guard let copyAllPtr = _copyAll else {
    print("IOReportCopyAllChannels not found")
    exit(1)
}

let IOReportCopyAllChannels = unsafeBitCast(copyAllPtr, to: IOReportCopyAllChannelsFn.self)

print("Enumerating IOReport channels…\n")

guard let rawArray = IOReportCopyAllChannels(0, 0) else {
    print("IOReportCopyAllChannels returned nil")
    exit(1)
}

// IOReportCopyAllChannels returns a CFDictionary with key "IOReportChannels" -> CFArray
let topDict = rawArray.takeRetainedValue() as! [String: Any]
print("Top-level keys: \(topDict.keys.sorted())\n")

// Extract the channels array
let channels: [[String: Any]]
if let arr = topDict["IOReportChannels"] as? [[String: Any]] {
    channels = arr
} else {
    // Try treating the whole dict as a flat channel list fallback
    print("Unexpected structure, dumping top dict:\n\(topDict)")
    exit(0)
}

print("Total channels: \(channels.count)\n")

// Collect all unique group names
var groups = Set<String>()
for ch in channels {
    if let g = ch["IOReportGroupName"] as? String { groups.insert(g) }
}
print("=== All Groups ===")
for g in groups.sorted() { print("  \(g)") }
print()

// Show channels matching display/disp/backlight/screen keywords
let keywords = ["disp", "display", "backlight", "screen", "scaler", "clcd", "dcp", "lcd", "pmp"]
print("=== Display-related channels ===")
var found = 0
for ch in channels {
    let group    = (ch["IOReportGroupName"]    as? String ?? "").lowercased()
    let subgroup = (ch["IOReportSubGroupName"] as? String ?? "").lowercased()
    let name     = (ch["IOReportChannelName"]  as? String ?? "").lowercased()
    let combined = group + " " + subgroup + " " + name
    if keywords.contains(where: { combined.contains($0) }) {
        print("  Group=\(ch["IOReportGroupName"] ?? "") | Sub=\(ch["IOReportSubGroupName"] ?? "") | Ch=\(ch["IOReportChannelName"] ?? "")")
        found += 1
    }
}
if found == 0 { print("  (none)") }

// Dump first Energy Model entry raw keys to find correct field names
print("\n=== Energy Model channels (LegendChannel[2]) ===")
for ch in channels {
    let g = ch["IOReportGroupName"] as? String ?? ""
    if g == "Energy Model" {
        if let legend = ch["LegendChannel"] as? [Any], legend.count >= 3 {
            let name = legend[2]
            print("  \(name)")
        }
    }
}

// Also check DCP Power subgroup for any watt/energy channel
print("\n=== DCP Power channels ===")
for ch in channels {
    let g = ch["IOReportGroupName"] as? String ?? ""
    let s = ch["IOReportSubGroupName"] as? String ?? ""
    if (g == "DCP" || g == "DCPEXT0" || g == "DCPEXT1") && s == "Power" {
        if let legend = ch["LegendChannel"] as? [Any], legend.count >= 3 {
            print("  Group=\(g) | Ch=\(legend[2])")
        }
    }
}
