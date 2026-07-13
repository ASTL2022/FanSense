#include "smc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (smc_open() != 0) { fprintf(stderr, "ERROR: open AppleSMC failed (need sudo?)\n"); return 1; }

    if (argc >= 2 && strcmp(argv[1], "auto") == 0) {
        int r0 = smc_write_uint8("F0Md", 0);
        int r1 = smc_write_uint8("F1Md", 0);
        printf("restore auto mode: F0Md=%s F1Md=%s\n", r0==0?"ok":"FAIL", r1==0?"ok":"FAIL");
        smc_close();
        return 0;
    }

    float rpm = 3000.0f;
    if (argc >= 2) rpm = atof(argv[1]);

    printf("setting manual mode + target %.0f rpm on both fans...\n", rpm);
    int m0 = smc_write_uint8("F0Md", 1);
    int m1 = smc_write_uint8("F1Md", 1);
    int t0 = smc_write_float("F0Tg", rpm);
    int t1 = smc_write_float("F1Tg", rpm);
    printf("write F0Md=%s F1Md=%s F0Tg=%s F1Tg=%s\n",
           m0==0?"ok":"FAIL", m1==0?"ok":"FAIL", t0==0?"ok":"FAIL", t1==0?"ok":"FAIL");

    sleep(3);
    float a0=0, a1=0, g0=0, g1=0;
    smc_read_float("F0Ac", &a0); smc_read_float("F1Ac", &a1);
    smc_read_float("F0Tg", &g0); smc_read_float("F1Tg", &g1);
    printf("after 3s: Fan0 cur=%.0f target=%.0f | Fan1 cur=%.0f target=%.0f\n", a0, g0, a1, g1);

    smc_close();
    return 0;
}
