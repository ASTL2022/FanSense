// NVMe SMART reader for Apple internal SSDs.
// Uses the IONVMeFamily user-client plug-in (same interface DriveDx/smartctl use).
// Works without root; internal NVMe only (external/USB drives don't expose it).

#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>

// From IONVMeFamily NVMeSMARTLibExternal.h (not shipped in the SDK)
#define kIONVMeSMARTUserClientTypeID CFUUIDGetConstantUUIDWithBytes(NULL, \
    0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, \
    0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)

#define kIONVMeSMARTInterfaceID CFUUIDGetConstantUUIDWithBytes(NULL, \
    0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, \
    0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)

// NVMe spec, Get Log Page 02h (SMART / Health Information), 512 bytes
#pragma pack(push, 1)
typedef struct {
    uint8_t  critical_warning;
    uint8_t  temperature[2];          // Kelvin, little-endian
    uint8_t  avail_spare;             // %
    uint8_t  spare_thresh;            // %
    uint8_t  percent_used;            // wear, %
    uint8_t  rsvd6[26];
    uint8_t  data_units_read[16];
    uint8_t  data_units_written[16];  // units of 512,000 bytes
    uint8_t  host_reads[16];
    uint8_t  host_writes[16];
    uint8_t  ctrl_busy_time[16];
    uint8_t  power_cycles[16];
    uint8_t  power_on_hours[16];
    uint8_t  unsafe_shutdowns[16];
    uint8_t  media_errors[16];
    uint8_t  num_err_log_entries[16];
    uint8_t  rsvd192[320];
} nvme_smart_log;
#pragma pack(pop)

typedef struct NVMeSMARTInterface {
    IUNKNOWN_C_GUTS;
    UInt16 version;
    UInt16 revision;
    IOReturn (*SMARTReadData)(void *interface, nvme_smart_log *data);
    IOReturn (*GetIdentifyData)(void *interface, void *identify, unsigned int ns);
    IOReturn (*GetFieldCounters)(void *interface, char *counters);
    IOReturn (*ScheduleBGRefresh)(void *interface);
    IOReturn (*GetLogPage)(void *interface, void *data, unsigned int logPageId, unsigned int bufferSize);
} NVMeSMARTInterface;

static uint64_t le128_lo64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static int nvme_read_smart(nvme_smart_log *out) {
    // Match any service advertising "NVMe SMART Capable" (IONVMeBlockDevice on
    // older stacks, IOEmbeddedNVMeBlockDevice on Apple Silicon).
    CFMutableDictionaryRef match = IOServiceMatching("IOService");
    CFMutableDictionaryRef prop = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(prop, CFSTR("NVMe SMART Capable"), kCFBooleanTrue);
    CFDictionarySetValue(match, CFSTR("IOPropertyMatch"), prop);
    CFRelease(prop);

    io_iterator_t it = IO_OBJECT_NULL;
    int ok = -1;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS)
        return -1;

    io_object_t svc;
    while ((svc = IOIteratorNext(it)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        if (IOCreatePlugInInterfaceForService(svc, kIONVMeSMARTUserClientTypeID,
                kIOCFPlugInInterfaceID, &plugin, &score) == KERN_SUCCESS && plugin) {
            NVMeSMARTInterface **smart = NULL;
            if ((*plugin)->QueryInterface(plugin,
                    CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
                    (LPVOID *)&smart) == S_OK && smart) {
                if ((*smart)->SMARTReadData(smart, out) == kIOReturnSuccess)
                    ok = 0;
                (*smart)->Release(smart);
            }
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(svc);
        if (ok == 0) break;
    }
    IOObjectRelease(it);
    return ok;
}

void print_smart(void) {
    nvme_smart_log s;
    memset(&s, 0, sizeof(s));
    if (nvme_read_smart(&s) != 0) {
        printf("smart_ok=0\n");
        return;
    }
    int health = 100 - (int)s.percent_used;
    if (health < 0) health = 0;
    unsigned kelvin = (unsigned)s.temperature[0] | ((unsigned)s.temperature[1] << 8);
    int tempC = kelvin > 273 ? (int)(kelvin - 273) : 0;
    double written_tb = (double)le128_lo64(s.data_units_written) * 512000.0 / 1e12;

    printf("smart_ok=1\n");
    printf("smart_health=%d\n", health);
    printf("smart_spare=%u\n", (unsigned)s.avail_spare);
    printf("smart_written_tb=%.1f\n", written_tb);
    printf("smart_temp=%d\n", tempC);
}
