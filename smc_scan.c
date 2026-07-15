// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

#include "smc.h"
#include <stdio.h>
#include <string.h>

// M1 Pro 常见温度传感器键值
static const char *temp_keys[] = {
    // CPU/SoC 温度
    "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0S",
    "Tp1C", "Tp1W", "Tp1b", "Tp1h", "Tp1l", "Tp1p", "Tp1t",
    // 传统 Intel 键（可能不存在）
    "TC0P", "TC0F", "TC0E", "TC0D",
    // GPU/ANE
    "Tg05", "Tg0D", "Tg0T",
    // 电池
    "TB0T", "TB1T", "TB2T",
    // Thunderbolt
    "TH0A", "TH0B", "TH0C",
    // 其他
    "TW0P", "Tm0P", "Ts0P", "Ts0S",
    NULL
};

// 电源/电池相关键
static const char *power_keys[] = {
    "BCLM", // 电池充电限制
    "B0PS", // 电池电源状态
    "B0RM", // 电池剩余容量
    "B0FC", // 电池满充容量
    "B0AV", // 电池电压
    "B0AC", // 电池电流
    NULL
};

int main(void) {
    if (smc_open() != 0) {
        fprintf(stderr, "ERROR: 无法打开 AppleSMC（需要 sudo）\n");
        return 1;
    }

    printf("=== M1 Pro (A2485) SMC 传感器扫描 ===\n\n");

    printf("【温度传感器】\n");
    for (int i = 0; temp_keys[i]; i++) {
        float val = 0;
        if (smc_read_float(temp_keys[i], &val) == 0) {
            printf("  ✓ %s = %.1f°C\n", temp_keys[i], val);
        }
    }

    printf("\n【电源/电池】\n");
    for (int i = 0; power_keys[i]; i++) {
        int val = 0;
        if (smc_read_int(power_keys[i], &val) == 0) {
            printf("  ✓ %s = %d (0x%04X)\n", power_keys[i], val, val);
        }
    }

    printf("\n【风扇信息】\n");
    int nfan = 0;
    smc_read_int("FNum", &nfan);
    printf("  风扇数量: %d\n", nfan);
    for (int i = 0; i < nfan; i++) {
        char k[5];
        float ac=0, mn=0, mx=0;
        snprintf(k, 5, "F%dAc", i); smc_read_float(k, &ac);
        snprintf(k, 5, "F%dMn", i); smc_read_float(k, &mn);
        snprintf(k, 5, "F%dMx", i); smc_read_float(k, &mx);
        printf("  Fan %d: 当前=%.0f rpm, 范围=[%.0f, %.0f]\n", i, ac, mn, mx);
    }

    smc_close();
    return 0;
}
