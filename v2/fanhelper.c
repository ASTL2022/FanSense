#include "smc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

// ── IOReport private API (loaded via dlopen/dlsym) ──

static CFDictionaryRef (*IOReportCopyChannelsInGroup)(CFStringRef, CFStringRef,
    uint64_t, uint64_t, uint64_t);
static void* (*IOReportCreateSubscription)(void*, CFDictionaryRef,
    CFMutableDictionaryRef*, uint64_t, void*);
static CFDictionaryRef (*IOReportCreateSamples)(void*, CFMutableDictionaryRef, void*);
static CFStringRef (*IOReportChannelGetChannelName)(void*);
static int64_t   (*IOReportSimpleGetIntegerValue)(void*, int);

static int ioreport_loaded = 0;

static int load_ioreport(void) {
    if (ioreport_loaded) return 1;
    void* h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
    if (!h) return 0;
    IOReportCopyChannelsInGroup  = dlsym(h, "IOReportCopyChannelsInGroup");
    IOReportCreateSubscription   = dlsym(h, "IOReportCreateSubscription");
    IOReportCreateSamples        = dlsym(h, "IOReportCreateSamples");
    IOReportChannelGetChannelName = dlsym(h, "IOReportChannelGetChannelName");
    IOReportSimpleGetIntegerValue = dlsym(h, "IOReportSimpleGetIntegerValue");
    if (!IOReportCopyChannelsInGroup || !IOReportCreateSubscription ||
        !IOReportCreateSamples || !IOReportChannelGetChannelName ||
        !IOReportSimpleGetIntegerValue) {
        dlclose(h);
        return 0;
    }
    ioreport_loaded = 1;
    return 1;
}

static void print_backlight(void) {
    if (!load_ioreport()) {
        fprintf(stderr, "ERROR: cannot load IOReport\n");
        return;
    }

    CFStringRef group = CFSTR("backlight report");
    CFDictionaryRef bl = IOReportCopyChannelsInGroup(group, NULL, 0, 0, 0);
    if (!bl) {
        fprintf(stderr, "ERROR: backlight report not available\n");
        return;
    }

    CFMutableDictionaryRef desired = CFDictionaryCreateMutableCopy(NULL, 0, bl);
    CFRelease(bl);

    CFMutableDictionaryRef subbed = NULL;
    void* sub = IOReportCreateSubscription(NULL, desired, &subbed, 0, NULL);
    CFRelease(desired);
    if (!sub) {
        fprintf(stderr, "ERROR: backlight subscription failed\n");
        return;
    }

    CFDictionaryRef sample = IOReportCreateSamples(sub, subbed, NULL);
    if (!sample) {
        fprintf(stderr, "ERROR: backlight sample failed\n");
        return;
    }

    CFArrayRef channels = CFDictionaryGetValue(sample, CFSTR("IOReportChannels"));
    if (!channels) {
        fprintf(stderr, "ERROR: no channels in backlight sample\n");
        CFRelease(sample);
        return;
    }

    long millinits = 0, microamps = 0, user_brightness = 0;
    long dpb_raw = 65536;

    for (long i = 0; i < CFArrayGetCount(channels); i++) {
        void* ch = (void*)CFArrayGetValueAtIndex(channels, i);
        CFStringRef name = IOReportChannelGetChannelName(ch);
        if (!name) continue;

        char nb[256] = {0};
        CFStringGetCString(name, nb, sizeof(nb), kCFStringEncodingUTF8);
        int64_t v = IOReportSimpleGetIntegerValue(ch, 0);

        if (strcmp(nb, "MilliNits value") == 0)      millinits = (long)v;
        else if (strcmp(nb, "MicroAmps value") == 0) microamps = (long)v;
        else if (strcmp(nb, "UserBrightness value") == 0) user_brightness = (long)v;
        else if (strcmp(nb, "DPB factor") == 0)      dpb_raw = (long)v;
    }

    CFRelease(sample);
    // Note: sub + subbed leak intentionally (one-shot call, process exits)

    printf("millinits=%ld\n", millinits);
    printf("microamps=%ld\n", microamps);
    printf("user_brightness=%ld\n", user_brightness);
    printf("dpb_factor=%ld\n", dpb_raw);
}

static void clamp_and_set(float rpm) {
    int n = 0;
    smc_read_int("FNum", &n);
    for (int i = 0; i < n; i++) {
        char k[5];
        float mn = 0, mx = 6000;
        snprintf(k, 5, "F%dMn", i); smc_read_float(k, &mn);
        snprintf(k, 5, "F%dMx", i); smc_read_float(k, &mx);
        float r = rpm;
        if (r < mn) r = mn;
        if (r > mx) r = mx;
        snprintf(k, 5, "F%dMd", i); smc_write_uint8(k, 1);
        snprintf(k, 5, "F%dTg", i); smc_write_float(k, r);
    }
}

static void set_auto(void) {
    int n = 0;
    smc_read_int("FNum", &n);
    for (int i = 0; i < n; i++) {
        char k[5];
        snprintf(k, 5, "F%dMd", i); smc_write_uint8(k, 0);
    }
}

static void print_state(void) {
    int n = 0;
    smc_read_int("FNum", &n);
    printf("count=%d\n", n);
    for (int i = 0; i < n; i++) {
        char k[5];
        float ac=0, mn=0, mx=0, tg=0; int md=0;
        snprintf(k, 5, "F%dAc", i); smc_read_float(k, &ac);
        snprintf(k, 5, "F%dMn", i); smc_read_float(k, &mn);
        snprintf(k, 5, "F%dMx", i); smc_read_float(k, &mx);
        snprintf(k, 5, "F%dTg", i); smc_read_float(k, &tg);
        snprintf(k, 5, "F%dMd", i); smc_read_int(k, &md);
        printf("%d cur=%.0f min=%.0f max=%.0f target=%.0f mode=%d\n",
               i, ac, mn, mx, tg, md);
    }
}

static void print_sensors(void) {
    float cpu_avg = 0, gpu = 0, batt_avg = 0;
    int cpu_count = 0, batt_count = 0;

    const char *cpu_keys[] = {"Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H", NULL};
    for (int i = 0; cpu_keys[i]; i++) {
        float t = 0;
        if (smc_read_float(cpu_keys[i], &t) == 0 && t > 0) {
            cpu_avg += t;
            cpu_count++;
        }
    }
    if (cpu_count > 0) cpu_avg /= cpu_count;

    smc_read_float("Tg0D", &gpu);

    const char *batt_keys[] = {"TB0T", "TB1T", "TB2T", NULL};
    for (int i = 0; batt_keys[i]; i++) {
        float t = 0;
        if (smc_read_float(batt_keys[i], &t) == 0 && t > 0) {
            batt_avg += t;
            batt_count++;
        }
    }
    if (batt_count > 0) batt_avg /= batt_count;

    int b0rm = 0, b0fc = 0, b0av = 0, b0ac = 0, b0ps = 0;
    smc_read_int("B0RM", &b0rm);
    smc_read_int("B0FC", &b0fc);
    smc_read_int("B0AV", &b0av);
    smc_read_int("B0AC", &b0ac);
    smc_read_int("B0PS", &b0ps);

    float pstr = 0, pdtr = 0;
    smc_read_float("PSTR", &pstr);
    smc_read_float("PDTR", &pdtr);

    printf("cpu_temp=%.1f\n", cpu_avg);
    printf("gpu_temp=%.1f\n", gpu);
    printf("battery_temp=%.1f\n", batt_avg);
    printf("battery_remaining=%d\n", b0rm);
    printf("battery_capacity=%d\n", b0fc);
    printf("battery_voltage=%d\n", b0av);
    printf("battery_current=%d\n", b0ac);
    printf("pstr=%.2f\n", pstr);
    printf("pdtr=%.2f\n", pdtr);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: fanhelper read|sensors|all|set <rpm>|auto\n");
        return 2;
    }
    if (smc_open() != 0) {
        fprintf(stderr, "ERROR: cannot open AppleSMC\n");
        return 1;
    }

    int rc = 0;
    if (strcmp(argv[1], "read") == 0) {
        print_state();
    } else if (strcmp(argv[1], "sensors") == 0) {
        print_sensors();
    } else if (strcmp(argv[1], "all") == 0) {
        print_state();
        printf("---\n");
        print_sensors();
    } else if (strcmp(argv[1], "set") == 0 && argc >= 3) {
        clamp_and_set((float)atof(argv[2]));
        print_state();
    } else if (strcmp(argv[1], "auto") == 0) {
        set_auto();
        print_state();
    } else {
        fprintf(stderr, "usage: fanhelper read|sensors|all|set <rpm>|auto\n");
        rc = 2;
    }

    smc_close();
    return rc;
}
