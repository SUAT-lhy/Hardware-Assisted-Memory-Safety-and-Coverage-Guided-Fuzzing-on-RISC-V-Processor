// afl_hlct_driver.c — AFL++ driver for HLCT hardware coverage
//
// Replaces AFL++'s software LLVM instrumentation with hardware coverage from
// the HLCT BRAM.  At startup, mmaps /dev/hlct_bram to get __afl_area_ptr;
// the hardware writes branch-edge hit counts directly into that memory region
// without any cache-coherency traffic.  The AFL++ fork server and fuzzing loop
// run unchanged; only the coverage source changes from LLVM SHM to BRAM mmap.
//
// Build: riscv64-unknown-linux-gnu-gcc -O2 -o afl_hlct_driver afl_hlct_driver.c
//        Link with your fuzz target: -Wl,--whole-archive afl_hlct_driver.o -Wl,--no-whole-archive
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <sys/wait.h>

#define HLCT_BRAM_SIZE    (64 * 1024)   /* 64 KB coverage map */
#define HLCT_DEV          "/dev/hlct_bram"
#define FORKSRV_FD        198           /* AFL++ fork-server pipe descriptor */

/* AFL++ shared memory pointer — override the default LLVM-instrumented one */
uint8_t *__afl_area_ptr;
uint8_t  __afl_area_initial[HLCT_BRAM_SIZE];

/* BRAM mmap handle */
static int    hlct_fd   = -1;
static void  *hlct_mmap = NULL;

/* ── Initialise: mmap BRAM and point __afl_area_ptr at it ────────────────
 * Called before main() via __attribute__((constructor)).                    */
__attribute__((constructor))
static void hlct_init(void)
{
    const char *shm_id_str;

    hlct_fd = open(HLCT_DEV, O_RDWR);
    if (hlct_fd < 0) {
        /* Fall back to software coverage (BRAM not available, e.g. x86 host) */
        shm_id_str = getenv("__AFL_SHM_ID");
        if (shm_id_str) {
            int shm_id = atoi(shm_id_str);
            __afl_area_ptr = shmat(shm_id, NULL, 0);
            if (__afl_area_ptr == (void *)-1)
                __afl_area_ptr = __afl_area_initial;
        } else {
            __afl_area_ptr = __afl_area_initial;
        }
        fprintf(stderr, "[hlct] /dev/hlct_bram not available — using SW coverage\n");
        return;
    }

    hlct_mmap = mmap(NULL, HLCT_BRAM_SIZE,
                     PROT_READ | PROT_WRITE, MAP_SHARED, hlct_fd, 0);
    if (hlct_mmap == MAP_FAILED) {
        close(hlct_fd);
        hlct_fd = -1;
        __afl_area_ptr = __afl_area_initial;
        perror("[hlct] mmap /dev/hlct_bram failed");
        return;
    }

    __afl_area_ptr = (uint8_t *)hlct_mmap;
    fprintf(stderr, "[hlct] BRAM coverage map mmapped at %p\n", hlct_mmap);
}

/* ── Clear coverage map between fuzzing iterations ───────────────────────
 * AFL++ calls this after reading the coverage bitmap.                       */
void __afl_map_shm(void)
{
    /* Hardware BRAM is already the shared map — nothing to remap */
}

/* ── Reset coverage counters before each test case ──────────────────────
 * Called by the AFL++ fork server just before exec'ing the target.          */
void hlct_reset_coverage(void)
{
    if (hlct_mmap)
        memset(hlct_mmap, 0, HLCT_BRAM_SIZE);
    else
        memset(__afl_area_ptr, 0, HLCT_BRAM_SIZE);
}

/* ── AFL++ persistent-mode loop shim ────────────────────────────────────
 * For targets that do not use AFL_LOOP(), provide a simple wrapper.         */
int __afl_persistent_loop(unsigned int max_cnt)
{
    static unsigned int cnt = 0;
    if (++cnt >= max_cnt) { cnt = 0; return 0; }
    hlct_reset_coverage();
    return 1;
}

/* ── Cleanup ─────────────────────────────────────────────────────────────*/
__attribute__((destructor))
static void hlct_fini(void)
{
    if (hlct_mmap && hlct_mmap != MAP_FAILED)
        munmap(hlct_mmap, HLCT_BRAM_SIZE);
    if (hlct_fd >= 0)
        close(hlct_fd);
}
