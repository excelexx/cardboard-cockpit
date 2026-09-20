/* motion_palette.h — Cinematic timing and blue-ramp light helpers for the
 * SPECTRE badge instrument (320x240 GFXcanvas8, palette indices 27..58 are the
 * 32-step blue ramp 0x0042..0xb7bf).
 *
 * Design contract:
 *  - Pure functions only: no dynamic allocation, no mutable state, no
 *    per-pixel trig or sqrt. Integer math everywhere except the two small
 *    float phase/easing helpers.
 *  - Bounded: every result is clamped to its documented range regardless of
 *    input, including absurd coordinates and very late (uint32) timestamps.
 *    All helpers saturate gracefully once their timeline has finished.
 *  - Overflow-safe: squared distances are guarded before squaring, and the
 *    repeating phase uses integer modulo so precision never degrades over a
 *    long-powered session.
 *
 * Only <stdint.h> is required.
 */
#ifndef MOTION_PALETTE_H
#define MOTION_PALETTE_H

#include <stdint.h>

namespace Cinematic {

/* Quadratic ease-out. t is clamped to [0,1]; result is in [0,1] with
 * easeOut(0)=0 and easeOut(1)=1. Decelerating curve: fast attack, soft
 * settle — reads as physical mass arriving, not a linear slide. */
inline float easeOut(float t) {
  if (!(t > 0.f)) return 0.f; // includes NaN and negative infinity
  if (t >= 1.f) return 1.f;
  return t * (2.f - t);
}

/* Ordered-dithered soft radial light, one pixel at a time.
 * Timeline: expands from radius 40 to 370 px over the first 900 ms, holds to
 * 950 ms, then fades to nothing by 1700 ms. Any elapsed >= 1700 (including
 * timestamps from long after the event) returns the dark ramp base 27.
 * Returns palette index 27..58. Pixels outside the current radius return 27,
 * so callers can cheaply early-out with a bounding box if desired.
 * The 4x4 Bayer matrix thresholds the fractional energy so the falloff
 * dissolves as film grain instead of banding — no sqrt, distances stay
 * squared. */
// Prepare once per frame. The Q16 reciprocal removes division from the pixel
// loop; this matters on the ESP32-C3 while BLE and LED tasks are also active.
struct BloomField {
  int cx, cy; int32_t radius2; uint32_t gain;
  uint8_t sample(int x,int y) const {
    if (!gain) return 27;
    int64_t wx=int64_t(x)-cx, wy=int64_t(y)-cy;
    if (wx>1024 || wx< -1024 || wy>1024 || wy< -1024) return 27;
    int32_t dx=int32_t(wx),dy=int32_t(wy),d2=dx*dx+dy*dy;
    if (d2>=radius2) return 27;
    // gain is constructed so this product is at most 512*65536.
    uint32_t energy=(uint32_t(radius2-d2)*gain)>>16;
    static const uint8_t bayer[4][4]={{0,8,2,10},{12,4,14,6},{3,11,1,9},{15,7,13,5}};
    uint32_t step=(energy>>4)+((energy&15)>bayer[y&3][x&3]?1:0);
    return uint8_t(27+(step>31?31:step));
  }
};
inline BloomField prepareBloom(uint32_t elapsed,int cx,int cy) {
  if (elapsed>=1700u) return {cx,cy,1,0};
  uint32_t grow=elapsed<900u?elapsed:900u;
  int32_t radius=40+int32_t(grow*330u/900u),radius2=radius*radius;
  uint32_t fade=elapsed>950u?1700u-elapsed:750u;
  uint32_t gain=uint32_t((uint64_t(512)*65536u*fade)/(uint64_t(radius2)*750u));
  return {cx,cy,radius2,gain};
}
inline uint8_t bloomIndex(int x,int y,uint32_t elapsed,int cx,int cy) {
  return prepareBloom(elapsed,cx,cy).sample(x,y);
}

/* Repeating perspective-grid phase in [0,1), period 1250 ms — identical cadence
 * to the previous fmodf(elapsed * 0.0008f, 1.f), but computed with integer
 * modulo so the wrap is exact and precision never decays at large elapsed. */
inline float launchTravel(uint32_t elapsed) {
  return float(elapsed % 1250u) * (1.f / 1250.f);
}

/* Debrief grade reveal progress in [0,1]. Tasteful delayed arrival: silent for
 * the first 1000 ms (score and track finish first), then eases in over 550 ms —
 * the same window the debrief scanline sweeps, so the two stay in sync.
 * Saturates at 1 for any later timestamp. */
inline float gradeArrival(uint32_t elapsed) {
  const uint32_t delay = 1000u, span = 550u;
  if (elapsed <= delay) return 0.f;
  uint32_t t = elapsed - delay;
  if (t >= span) return 1.f;
  return easeOut(float(t) * (1.f / float(span)));
}

/* Brief blue discharge falloff for the weapon pulse, one point at a time.
 * distance: pixels from the muzzle/beam origin (sign ignored).
 * A bright ring front races outward at ~1.33 px/ms with a 48 px wide crest,
 * leaving a shorter, dimmer afterglow inside; the whole event dies by 300 ms.
 * After 300 ms (or at extreme distance) returns the dark base 27.
 * Returns palette index 27..58. Integer-only, no sqrt (caller supplies the
 * distance; along a horizontal streak it is just |x - muzzleX|). */
inline uint8_t dischargeIndex(int distance, uint32_t elapsed) {
  const uint8_t base = 27;
  const uint32_t duration = 300u;
  if (distance > 1024 || distance < -1024) return base;
  if (distance < 0) distance = -distance;
  if (elapsed >= duration) return base;
  int32_t ring = int32_t(elapsed) * 4 / 3;            /* wavefront px */
  int32_t timeFade = int32_t(duration - elapsed);     /* 1..300 */
  int32_t dd = int32_t(distance) - ring;
  if (dd < 0) dd = -dd;
  int32_t ringE = dd < 48 ? (48 - dd) * 31 / 48 : 0;  /* crest 0..31 */
  int32_t inside = ring - int32_t(distance);
  int32_t glowE = inside > 0 && inside < 160 ? (160 - inside) * 12 / 160 : 0;
  int32_t e = ringE > glowE ? ringE : glowE;          /* 0..31 */
  e = e * timeFade / int32_t(duration);
  if (e > 31) e = 31;
  return uint8_t(base + e);
}

} // namespace Cinematic

#endif // MOTION_PALETTE_H
