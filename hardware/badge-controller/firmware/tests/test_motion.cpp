/* test_motion.cpp — host-side boundary/range/inactivity checks for
 * motion_palette.h. No hardware libraries; build and run anywhere:
 *   c++ -std=c++11 -Wall -Wextra test_motion.cpp -o test_motion && ./test_motion
 */
#include "motion_palette.h"
#include <cassert>
#include <cstdio>
#include <cmath>
#include <climits>
#include <limits>

using namespace Cinematic;

static void testEaseOut() {
  assert(easeOut(std::numeric_limits<float>::quiet_NaN()) == 0.f);
  assert(easeOut(-std::numeric_limits<float>::infinity()) == 0.f);
  assert(easeOut(std::numeric_limits<float>::infinity()) == 1.f);
  assert(easeOut(-1.f) == 0.f);
  assert(easeOut(0.f) == 0.f);
  assert(easeOut(1.f) == 1.f);
  assert(easeOut(2.5f) == 1.f);
  assert(std::fabs(easeOut(0.5f) - 0.75f) < 1e-6f); /* fast attack */
  float prev = -1.f;
  for (int i = 0; i <= 100; i++) {
    float v = easeOut(i / 100.f);
    assert(v >= prev && v >= 0.f && v <= 1.f); /* monotonic, bounded */
    prev = v;
  }
}

static void testBloomIndex() {
  assert(bloomIndex(INT_MAX, INT_MIN, 450, INT_MIN, INT_MAX) == 27);
  const int xs[] = {-50, 0, 1, 159, 318, 319, 400};
  const int ys[] = {-50, 0, 1, 119, 238, 239, 400};
  const uint32_t ts[] = {0u, 100u, 450u, 900u, 951u, 1200u, 1650u, 1700u,
                         1701u, 5000u, 4000000000u, 0xffffffffu};
  for (int x : xs) for (int y : ys) for (uint32_t t : ts) {
    uint8_t v = bloomIndex(x, y, t, 160, 120);
    assert(v >= 27 && v <= 58); /* range, incl. absurd coords and late stamps */
  }
  /* Centre beats corner mid-expansion. */
  assert(bloomIndex(160, 120, 450, 160, 120) > bloomIndex(10, 10, 450, 160, 120));
  /* Inactivity: event over -> dark ramp base. */
  assert(bloomIndex(160, 120, 1700, 160, 120) == 27);
  assert(bloomIndex(160, 120, 0xffffffffu, 160, 120) == 27);
  /* Outside the radius -> dark ramp base. */
  assert(bloomIndex(0, 0, 100, 160, 120) == 27);
  /* Brightest reachable step exists near the core at full strength. */
  assert(bloomIndex(160, 120, 900, 160, 120) == 58);
}

static void testLaunchTravel() {
  assert(launchTravel(0) == 0.f);
  assert(std::fabs(launchTravel(625) - 0.5f) < 1e-3f);
  assert(launchTravel(1250) == 0.f);          /* exact wrap */
  assert(launchTravel(1251) > 0.f && launchTravel(1251) < 0.01f);
  const uint32_t ts[] = {0u, 1u, 1249u, 1250u, 999999u, 4000000000u, 0xffffffffu};
  for (uint32_t t : ts) {
    float v = launchTravel(t);
    assert(v >= 0.f && v < 1.f); /* bounded even at huge elapsed */
  }
}

static void testGradeArrival() {
  assert(gradeArrival(0) == 0.f);
  assert(gradeArrival(999) == 0.f);
  assert(gradeArrival(1000) == 0.f);          /* still silent at the delay */
  assert(gradeArrival(1550) == 1.f);
  assert(gradeArrival(2000) == 1.f);
  assert(gradeArrival(0xffffffffu) == 1.f);   /* late timestamp saturates */
  float prev = -1.f;
  for (uint32_t t = 1000; t <= 1550; t += 25) {
    float v = gradeArrival(t);
    assert(v >= prev && v >= 0.f && v <= 1.f); /* monotonic reveal */
    prev = v;
  }
  /* ease-out shape, not linear: halfway through the window it is ~0.75. */
  assert(gradeArrival(1275) > 0.7f && gradeArrival(1275) < 0.8f);
}

static void testDischargeIndex() {
  assert(dischargeIndex(INT_MIN, 100) == 27);
  assert(dischargeIndex(INT_MAX, 100) == 27);
  for (int d = -10; d <= 500; d += 7)
    for (uint32_t t = 0; t <= 400; t += 13) {
      uint8_t v = dischargeIndex(d, t);
      assert(v >= 27 && v <= 58); /* range, incl. negative distance */
    }
  /* Inactivity: pulse over -> dark ramp base at any distance. */
  assert(dischargeIndex(0, 300) == 27);
  assert(dischargeIndex(100, 0xffffffffu) == 27);
  /* Far from the front -> dark. */
  assert(dischargeIndex(10000, 100) == 27);
  /* At the wavefront (ring = 150 * 4/3 = 200 px) the crest is clearly lit
   * (timeFade halves the peak by mid-event, so expect ~15 steps). */
  assert(dischargeIndex(200, 150) > 27 + 12);
  /* Crest is brighter than the trailing afterglow. */
  assert(dischargeIndex(200, 150) > dischargeIndex(100, 150));
  /* Negative distance is treated as the origin, not UB. */
  assert(dischargeIndex(-200, 150) == dischargeIndex(200, 150));
}

int main() {
  testEaseOut();
  testBloomIndex();
  testLaunchTravel();
  testGradeArrival();
  testDischargeIndex();
  std::printf("test_motion: all checks passed\n");
  return 0;
}
