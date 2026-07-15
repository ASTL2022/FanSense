// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dr.t @ MarsCandyBox

#ifndef SMC_H
#define SMC_H

#include <stdint.h>

int  smc_open(void);
void smc_close(void);

int      smc_read_int(const char *key, int *out);
int      smc_read_float(const char *key, float *out);
int      smc_write_uint8(const char *key, uint8_t val);
int      smc_write_float(const char *key, float val);

#endif
