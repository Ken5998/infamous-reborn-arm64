/*
 * x86 SIMD intrinsics on Windows ARM64.
 *
 * inFAMOUS Reborn's runtime includes the x86 intrinsic headers (<emmintrin.h>, <smmintrin.h>,
 * <x86intrin.h>, ...). For an ARM64 build this folder comes first on the include path, so those
 * names land here and get SSE through sse2neon (NEON underneath). AVX/AVX2 stay off: the runtime
 * keeps an SSE twin of every AVX2 path behind #if __AVX2__. The 128-bit FMA3 forms (the lifted SPU
 * code's float multiply-adds) are added below, so the build defines __FMA__.
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

/* FMA3, 128-bit: one rounding like vfmadd/vfmsub/vfnmadd/vfnmsub. NEON's vfmaq(c, a, b) is
 * c + a*b and vfmsq(c, a, b) is c - a*b, both fused; negating an operand or result is exact. */
#ifndef INFAMOUS_HAVE_FMA
#define INFAMOUS_HAVE_FMA 1
#define INFAMOUS_FMA_INLINE static __inline__ __attribute__((always_inline))
INFAMOUS_FMA_INLINE __m128 _mm_fmadd_ps(__m128 a, __m128 b, __m128 c)  { return vfmaq_f32(c, a, b); }
INFAMOUS_FMA_INLINE __m128 _mm_fmsub_ps(__m128 a, __m128 b, __m128 c)  { return vfmaq_f32(vnegq_f32(c), a, b); }
INFAMOUS_FMA_INLINE __m128 _mm_fnmadd_ps(__m128 a, __m128 b, __m128 c) { return vfmsq_f32(c, a, b); }
INFAMOUS_FMA_INLINE __m128 _mm_fnmsub_ps(__m128 a, __m128 b, __m128 c) { return vnegq_f32(vfmaq_f32(c, a, b)); }
INFAMOUS_FMA_INLINE __m128d _mm_fmadd_pd(__m128d a, __m128d b, __m128d c)  { return vreinterpretq_m128d_f64(vfmaq_f64(vreinterpretq_f64_m128d(c), vreinterpretq_f64_m128d(a), vreinterpretq_f64_m128d(b))); }
INFAMOUS_FMA_INLINE __m128d _mm_fmsub_pd(__m128d a, __m128d b, __m128d c)  { return vreinterpretq_m128d_f64(vfmaq_f64(vnegq_f64(vreinterpretq_f64_m128d(c)), vreinterpretq_f64_m128d(a), vreinterpretq_f64_m128d(b))); }
INFAMOUS_FMA_INLINE __m128d _mm_fnmadd_pd(__m128d a, __m128d b, __m128d c) { return vreinterpretq_m128d_f64(vfmsq_f64(vreinterpretq_f64_m128d(c), vreinterpretq_f64_m128d(a), vreinterpretq_f64_m128d(b))); }
INFAMOUS_FMA_INLINE __m128d _mm_fnmsub_pd(__m128d a, __m128d b, __m128d c) { return vreinterpretq_m128d_f64(vnegq_f64(vfmaq_f64(vreinterpretq_f64_m128d(c), vreinterpretq_f64_m128d(a), vreinterpretq_f64_m128d(b)))); }
#endif

#endif /* __aarch64__ */
#endif /* INFAMOUS_ARM64_X86_COMPAT_H */
