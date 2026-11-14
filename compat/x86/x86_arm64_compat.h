/*
 * x86 SIMD intrinsics on Windows ARM64.
 *
 * inFAMOUS Reborn's runtime includes the x86 intrinsic headers (<emmintrin.h>, <smmintrin.h>,
 * <x86intrin.h>, ...). For an ARM64 build this folder comes first on the include path, so those
 * names land here and get SSE through sse2neon (NEON underneath). AVX/AVX2 stay off: the runtime
 * keeps an SSE twin of every AVX2 path behind #if __AVX2__.
 */
#ifndef INFAMOUS_ARM64_X86_COMPAT_H
#define INFAMOUS_ARM64_X86_COMPAT_H

#if defined(__aarch64__) || defined(_M_ARM64)

#include "sse2neon.h"
#include <stdint.h>

/* __rdtsc: the runtime only uses it for cycle counts in its stats and spin timers. The ARM
 * generic timer counts at a fixed rate (19.2 MHz on Snapdragon), which is what they need. */
#ifndef INFAMOUS_HAVE_RDTSC
#define INFAMOUS_HAVE_RDTSC 1
static __inline__ __attribute__((always_inline)) uint64_t infamous_rdtsc(void)
{
    uint64_t v;
    __asm__ __volatile__("mrs %0, cntvct_el0" : "=r"(v));
    return v;
}
#define __rdtsc() infamous_rdtsc()
#define _rdtsc()  infamous_rdtsc()
#define __builtin_ia32_rdtsc() infamous_rdtsc()
#define __builtin_ia32_pause() _mm_pause()
#endif

#endif /* __aarch64__ */
#endif /* INFAMOUS_ARM64_X86_COMPAT_H */
