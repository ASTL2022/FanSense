// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

#include "smc.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (smc_open() != 0) {
        fprintf(stderr, "ERROR: cannot open AppleSMC\n");
        return 1;
    }

    int n = 0;
    if (smc_read_int("FNum", &n) != 0) {
        fprintf(stderr, "ERROR: cannot read FNum\n");
        smc_close();
        return 1;
    }
    printf("FNum (fan count) = %d\n", n);

    for (int i = 0; i < n; i++) {
        char k[5];
        float ac = 0, mn = 0, mx = 0, tg = 0; int md = 0;
        snprintf(k, 5, "F%dAc", i); smc_read_float(k, &ac);
        snprintf(k, 5, "F%dMn", i); smc_read_float(k, &mn);
        snprintf(k, 5, "F%dMx", i); smc_read_float(k, &mx);
        snprintf(k, 5, "F%dTg", i); smc_read_float(k, &tg);
        snprintf(k, 5, "F%dMd", i); smc_read_int(k, &md);
        printf("Fan %d: cur=%.0f rpm  min=%.0f  max=%.0f  target=%.0f  mode=%d\n",
               i, ac, mn, mx, tg, md);
    }

    smc_close();
    return 0;
}
