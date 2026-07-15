// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>
#include <stdio.h>

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

typedef struct {
    char     major, minor, build, reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char     dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    uint32_t                key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    char                    result;
    char                    status;
    char                    data8;
    uint32_t                data32;
    SMCBytes_t              bytes;
} SMCKeyData_t;

static io_connect_t g_conn = 0;

static uint32_t key_to_u32(const char *key) {
    return ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) |
           ((uint32_t)key[2] << 8)  |  (uint32_t)key[3];
}

int smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    return r == kIOReturnSuccess ? 0 : -1;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

static int smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t outSize = sizeof(SMCKeyData_t);
    kern_return_t r = IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC,
                                                in, sizeof(SMCKeyData_t),
                                                out, &outSize);
    return r == kIOReturnSuccess ? 0 : -1;
}

static int read_key(const char *key, SMCKeyData_keyInfo_t *ki, SMCBytes_t bytes) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key  = key_to_u32(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != 0) return -1;

    *ki = out.keyInfo;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key  = key_to_u32(key);
    in.keyInfo.dataSize = ki->dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&in, &out) != 0) return -1;

    memcpy(bytes, out.bytes, sizeof(SMCBytes_t));
    return 0;
}

int smc_read_int(const char *key, int *out) {
    SMCKeyData_keyInfo_t ki;
    SMCBytes_t b;
    if (read_key(key, &ki, b) != 0) return -1;
    if (ki.dataSize == 4) {
        *out = ((unsigned char)b[0] << 24) | ((unsigned char)b[1] << 16) |
               ((unsigned char)b[2] << 8)  |  (unsigned char)b[3];
    } else if (ki.dataSize == 2) {
        *out = ((unsigned char)b[0] << 8) | (unsigned char)b[1];
    } else {
        *out = (unsigned char)b[0];
    }
    return 0;
}

int smc_read_float(const char *key, float *out) {
    SMCKeyData_keyInfo_t ki;
    SMCBytes_t b;
    if (read_key(key, &ki, b) != 0) return -1;
    uint32_t type = ki.dataType;
    if (type == key_to_u32("flt ")) {
        memcpy(out, b, 4);
    } else if (type == key_to_u32("fpe2")) {
        int v = ((unsigned char)b[0] << 8) | (unsigned char)b[1];
        *out = (float)(v >> 2);
    } else if (type == key_to_u32("fp2e")) {
        int v = ((unsigned char)b[0] << 8) | (unsigned char)b[1];
        *out = (float)v / 16384.0f;
    } else {
        memcpy(out, b, 4);
    }
    return 0;
}

static int write_bytes(const char *key, SMCBytes_t bytes, uint32_t size) {
    SMCKeyData_keyInfo_t ki;
    SMCBytes_t cur;
    if (read_key(key, &ki, cur) != 0) return -1;

    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key_to_u32(key);
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.keyInfo.dataSize = size ? size : ki.dataSize;
    memcpy(in.bytes, bytes, sizeof(SMCBytes_t));
    return smc_call(&in, &out);
}

int smc_write_uint8(const char *key, uint8_t val) {
    SMCBytes_t b;
    memset(b, 0, sizeof(b));
    b[0] = val;
    return write_bytes(key, b, 1);
}

int smc_write_float(const char *key, float val) {
    SMCBytes_t b;
    memset(b, 0, sizeof(b));
    memcpy(b, &val, 4);
    return write_bytes(key, b, 4);
}
