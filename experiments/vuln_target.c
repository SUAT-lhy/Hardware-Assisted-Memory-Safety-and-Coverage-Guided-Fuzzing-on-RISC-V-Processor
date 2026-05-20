#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int process(char *buf, int len) {
    char tmp[64];
    if (len > 0 && len < 120) {
        memcpy(tmp, buf, len);
        tmp[len] = 0;
        if (tmp[0]=='F' && tmp[1]=='U' && tmp[2]=='Z') return 1;
        if (tmp[0]=='A') { int x=0; while(x<len) x++; return 2; }
        if (tmp[0]=='B' && tmp[1]=='B') return 3;
    }
    return 0;
}

int main(int argc, char **argv) {
    char buf[256]; int n;
    FILE *f = (argc > 1) ? fopen(argv[1], "rb") : stdin;
    if (!f) return 1;
    n = fread(buf, 1, sizeof(buf)-1, f);
    if (argc > 1) fclose(f);
    return process(buf, n);
}
