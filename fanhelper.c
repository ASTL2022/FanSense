// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

#include "smc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>

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
    float cpu_avg = 0, gpu_avg = 0, batt_avg = 0;
    int cpu_count = 0, gpu_count = 0, batt_count = 0;

    // P/E-core die sensors across M1-M4 generations; missing keys read 0 and are skipped.
    const char *cpu_keys[] = {
        "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H",                   // M1/M2
        "Tp0V", "Tp0Y", "Tp0b", "Tp0e",                           // M3/M4 P-core
        "Te05", "Te09", "Te0H", "Te0S", "Te0L", "Te0P",           // M3/M4 E-core
        NULL};
    for (int i = 0; cpu_keys[i]; i++) {
        float t = 0;
        if (smc_read_float(cpu_keys[i], &t) == 0 && t > 0) {
            cpu_avg += t;
            cpu_count++;
        }
    }
    if (cpu_count > 0) cpu_avg /= cpu_count;

    const char *gpu_keys[] = {
        "Tg0D", "Tg05", "Tg0L", "Tg0T",                           // M1
        "Tg0f", "Tg0n",                                           // M2
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A", // M3
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0j", "Tg0k", // M4
        NULL};
    for (int i = 0; gpu_keys[i]; i++) {
        float t = 0;
        if (smc_read_float(gpu_keys[i], &t) == 0 && t > 0) {
            gpu_avg += t;
            gpu_count++;
        }
    }
    if (gpu_count > 0) gpu_avg /= gpu_count;

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
    printf("gpu_temp=%.1f\n", gpu_avg);
    printf("battery_temp=%.1f\n", batt_avg);
    printf("battery_remaining=%d\n", b0rm);
    printf("battery_capacity=%d\n", b0fc);
    printf("battery_voltage=%d\n", b0av);
    printf("battery_current=%d\n", b0ac);
    printf("pstr=%.2f\n", pstr);
    printf("pdtr=%.2f\n", pdtr);
}

// Bump whenever helper commands/output change, so the app can prompt to reinstall.
#define HELPER_VERSION "4"

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: fanhelper version|read|sensors|all|smart|set <rpm>|auto\n");
        return 2;
    }
    if (strcmp(argv[1], "version") == 0) {
        printf("%s\n", HELPER_VERSION);
        return 0;
    }
    extern void print_smart(void);
    if (strcmp(argv[1], "smart") == 0) {
        print_smart();          // no SMC needed
        return 0;
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
        fprintf(stderr, "usage: fanhelper read|sensors|all|smart|set <rpm>|auto\n");
        rc = 2;
    }

    smc_close();
    return rc;
}
