// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

// smc_dump.c — 枚举全部 SMC key 并解码值，用于定位"放电整机功耗" key。
// 独立实现，不依赖 smc.c（避免影响正在使用的 helper）。
//
// 编译:  clang -O2 -framework IOKit -framework CoreFoundation smc_dump.c -o smc_dump
// 用法:  ./smc_dump            列出全部 key
//        ./smc_dump P          只列出 P 开头的 key（功耗类）
//        ./smc_dump watch P    每秒刷新 P 开头的 key，观察放电时哪个在变
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

#define KERNEL_INDEX_SMC     2
#define CMD_READ_BYTES       5
#define CMD_READ_KEYINFO     9
#define CMD_READ_INDEX       8

typedef struct { char major, minor, build, reserved[1]; uint16_t release; } vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } plimit_t;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } keyinfo_t;
typedef char SMCBytes_t[32];

typedef struct {
    uint32_t   key;
    vers_t     vers;
    plimit_t   pLimitData;
    keyinfo_t  keyInfo;
    char       result, status, data8;
    uint32_t   data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t g_conn = 0;

static uint32_t s2k(const char *s) {
    return ((uint32_t)s[0]<<24)|((uint32_t)s[1]<<16)|((uint32_t)s[2]<<8)|(uint32_t)s[3];
}
static void k2s(uint32_t k, char *out) {
    out[0]=(k>>24)&0xFF; out[1]=(k>>16)&0xFF; out[2]=(k>>8)&0xFF; out[3]=k&0xFF; out[4]=0;
}
static void t2s(uint32_t t, char *out) { k2s(t, out); }

static int smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t os = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sizeof(*in), out, &os)
           == kIOReturnSuccess ? 0 : -1;
}

static int smc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    return r == kIOReturnSuccess ? 0 : -1;
}

static uint32_t key_count(void) {
    SMCKeyData_t in = {0}, out = {0};
    in.key = s2k("#KEY"); in.data8 = CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != 0) return 0;
    keyinfo_t ki = out.keyInfo;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = s2k("#KEY"); in.keyInfo.dataSize = ki.dataSize; in.data8 = CMD_READ_BYTES;
    if (smc_call(&in, &out) != 0) return 0;
    return ((uint8_t)out.bytes[0]<<24)|((uint8_t)out.bytes[1]<<16)|
           ((uint8_t)out.bytes[2]<<8)|(uint8_t)out.bytes[3];
}

static int key_by_index(uint32_t idx, char *keyOut) {
    SMCKeyData_t in = {0}, out = {0};
    in.data8 = CMD_READ_INDEX; in.data32 = idx;
    if (smc_call(&in, &out) != 0) return -1;
    k2s(out.key, keyOut);
    return 0;
}

static int read_key(const char *key, keyinfo_t *ki, SMCBytes_t bytes) {
    SMCKeyData_t in = {0}, out = {0};
    in.key = s2k(key); in.data8 = CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != 0) return -1;
    *ki = out.keyInfo;
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = s2k(key); in.keyInfo.dataSize = ki->dataSize; in.data8 = CMD_READ_BYTES;
    if (smc_call(&in, &out) != 0) return -1;
    memcpy(bytes, out.bytes, sizeof(SMCBytes_t));
    return 0;
}

// 把一个 key 解码成人类可读字符串，写入 valOut。返回 1 = 解码成功。
static int decode(const char *key, char *typeOut, char *valOut, size_t n) {
    keyinfo_t ki; SMCBytes_t b;
    if (read_key(key, &ki, b) != 0) { typeOut[0]=0; valOut[0]=0; return 0; }
    t2s(ki.dataType, typeOut);
    uint32_t T = ki.dataType, sz = ki.dataSize;

    if (T == s2k("flt ")) { float f; memcpy(&f, b, 4); snprintf(valOut, n, "%.3f", f); }
    else if (T == s2k("fpe2")) { int v=((uint8_t)b[0]<<8)|(uint8_t)b[1]; snprintf(valOut,n,"%.2f",(float)(v>>2)); }
    else if (T == s2k("fp2e")) { int v=((uint8_t)b[0]<<8)|(uint8_t)b[1]; snprintf(valOut,n,"%.4f",(float)v/16384.0f); }
    else if (T == s2k("fp1f")) { int v=((uint8_t)b[0]<<8)|(uint8_t)b[1]; snprintf(valOut,n,"%.5f",(float)v/32768.0f); }
    else if (T == s2k("ui8 ") || (sz==1)) { snprintf(valOut,n,"%u",(uint8_t)b[0]); }
    else if (T == s2k("ui16") || sz==2) { snprintf(valOut,n,"%u",((uint8_t)b[0]<<8)|(uint8_t)b[1]); }
    else if (T == s2k("ui32") || sz==4) {
        uint32_t v=((uint8_t)b[0]<<24)|((uint8_t)b[1]<<16)|((uint8_t)b[2]<<8)|(uint8_t)b[3];
        snprintf(valOut,n,"%u",v);
    }
    else if (T == s2k("si16")) { int16_t v=((uint8_t)b[0]<<8)|(uint8_t)b[1]; snprintf(valOut,n,"%d",v); }
    else if (T == s2k("si8 ")) { snprintf(valOut,n,"%d",(int8_t)b[0]); }
    else {
        snprintf(valOut, n, "raw[%u]=%02x%02x%02x%02x", sz,
                 (uint8_t)b[0],(uint8_t)b[1],(uint8_t)b[2],(uint8_t)b[3]);
    }
    return 1;
}

static void dump_once(const char *prefix) {
    uint32_t n = key_count();
    char key[5], type[5], val[64];
    int shown = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (key_by_index(i, key) != 0) continue;
        if (prefix && prefix[0] && strncmp(key, prefix, strlen(prefix)) != 0) continue;
        if (!decode(key, type, val, sizeof(val))) continue;
        printf("  %-4s [%-4s] = %s\n", key, type, val);
        shown++;
    }
    if (prefix && prefix[0]) printf("  (%d keys matching \"%s\", total %u)\n", shown, prefix, n);
    else printf("  (total %u keys)\n", n);
}

int main(int argc, char **argv) {
    if (smc_open() != 0) { fprintf(stderr, "ERROR: 无法打开 AppleSMC\n"); return 1; }

    int watch = 0;
    const char *prefix = "";
    if (argc >= 2 && strcmp(argv[1], "watch") == 0) { watch = 1; prefix = argc >= 3 ? argv[2] : ""; }
    else if (argc >= 2) prefix = argv[1];

    if (watch) {
        for (;;) {
            printf("\033[2J\033[H");  // clear screen
            printf("=== SMC %s keys (每秒刷新, Ctrl-C 退出) ===\n",
                   prefix[0] ? prefix : "ALL");
            dump_once(prefix);
            fflush(stdout);
            sleep(1);
        }
    } else {
        printf("=== SMC key dump%s%s ===\n", prefix[0] ? " · prefix=" : "", prefix);
        dump_once(prefix);
    }
    IOServiceClose(g_conn);
    return 0;
}
