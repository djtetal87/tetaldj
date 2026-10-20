#pragma once
// Per-deck insert effect, applied after EQ / filter / fader. One slot with a
// type, a wet amount (0..1) and a beat length for the tempo-synced ones.
// Parameters are atomics written from the UI thread and read per block.
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <vector>

static constexpr double kFxPi = 3.14159265358979323846;

enum DeckFxType : int {
  kFxNone = 0,
  kFxEcho = 1,
  kFxReverb = 2,
  kFxFlanger = 3,
  kFxPhaser = 4,
  kFxCrush = 5,
  kFxGate = 6,
};

class DeckFx {
 public:
  std::atomic<int> type{kFxNone};
  std::atomic<float> amount{0.0f};
  std::atomic<float> beats{0.5f};

  void prepare(int sampleRate) {
    if (sampleRate == sr_) return;
    sr_ = std::max(8000, sampleRate);
    delayL_.assign((size_t)sr_ * 4, 0.0f);
    delayR_.assign((size_t)sr_ * 4, 0.0f);
    delayPos_ = 0;
    modL_.assign((size_t)sr_ / 20, 0.0f);  // 50 ms modulated delay
    modR_.assign((size_t)sr_ / 20, 0.0f);
    modPos_ = 0;
    initReverb();
    reset();
  }

  void reset() {
    std::fill(delayL_.begin(), delayL_.end(), 0.0f);
    std::fill(delayR_.begin(), delayR_.end(), 0.0f);
    std::fill(modL_.begin(), modL_.end(), 0.0f);
    std::fill(modR_.begin(), modR_.end(), 0.0f);
    for (auto& c : combs_) std::fill(c.buf.begin(), c.buf.end(), 0.0f);
    for (auto& a : allp_) std::fill(a.buf.begin(), a.buf.end(), 0.0f);
    fbLpL_ = fbLpR_ = 0.0f;
    phase_ = 0.0;
    holdL_ = holdR_ = 0.0f;
    holdCount_ = 0;
    for (auto& z : phZL_) z = 0.0f;
    for (auto& z : phZR_) z = 0.0f;
    wetSmooth_ = 0.0f;
  }

  // In place, interleaved-free (two planar buffers). bpm already includes rate.
  void process(float* l, float* r, int frames, double bpm) {
    const int t = type.load(std::memory_order_relaxed);
    const float target = t == kFxNone ? 0.0f : std::clamp(amount.load(), 0.0f, 1.0f);
    if (target <= 0.0005f && wetSmooth_ <= 0.0005f) {
      wetSmooth_ = 0.0f;
      return;
    }
    if (delayL_.empty()) prepare(48000);
    const double beatSec = bpm > 20.0 ? 60.0 / bpm : 0.5;
    const float b = std::clamp(beats.load(), 0.0625f, 8.0f);
    switch (t) {
      case kFxEcho: echo(l, r, frames, target, beatSec * b); break;
      case kFxReverb: reverb(l, r, frames, target); break;
      case kFxFlanger: flanger(l, r, frames, target, beatSec * b); break;
      case kFxPhaser: phaser(l, r, frames, target, beatSec * b); break;
      case kFxCrush: crush(l, r, frames, target); break;
      case kFxGate: gate(l, r, frames, target, beatSec * b); break;
      default:
        // Type switched to none: let the smoothing fade out whatever is left.
        for (int i = 0; i < frames; ++i) wetSmooth_ += (0.0f - wetSmooth_) * 0.002f;
        break;
    }
  }

 private:
  int sr_ = 0;

  // ---- echo
  std::vector<float> delayL_, delayR_;
  size_t delayPos_ = 0;
  float fbLpL_ = 0.0f, fbLpR_ = 0.0f;
  float wetSmooth_ = 0.0f;

  void echo(float* l, float* r, int n, float target, double seconds) {
    const size_t len = delayL_.size();
    const size_t d = (size_t)std::clamp(seconds * sr_, 1.0, (double)len - 1);
    const float feedback = 0.45f + 0.35f * target;
    const float lp = 0.35f;  // darker repeats
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      const size_t rp = (delayPos_ + len - d) % len;
      const float dl = delayL_[rp];
      const float dr = delayR_[rp];
      fbLpL_ += (dl - fbLpL_) * lp;
      fbLpR_ += (dr - fbLpR_) * lp;
      delayL_[delayPos_] = l[i] * wetSmooth_ + fbLpL_ * feedback;
      delayR_[delayPos_] = r[i] * wetSmooth_ + fbLpR_ * feedback;
      l[i] = l[i] * (1.0f - 0.25f * wetSmooth_) + dl * 0.7f;
      r[i] = r[i] * (1.0f - 0.25f * wetSmooth_) + dr * 0.7f;
      delayPos_ = (delayPos_ + 1) % len;
    }
  }

  // ---- reverb (Freeverb-style, mono-summed input, stereo spread)
  struct Comb {
    std::vector<float> buf;
    size_t pos = 0;
    float store = 0.0f;
  };
  struct Allpass {
    std::vector<float> buf;
    size_t pos = 0;
  };
  Comb combs_[8];
  Allpass allp_[4];

  void initReverb() {
    static const int combTunes[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
    static const int allpTunes[4] = {556, 441, 341, 225};
    const double scale = sr_ / 44100.0;
    for (int i = 0; i < 8; ++i) {
      const int extra = i >= 4 ? 23 : 0;  // right channel spread
      combs_[i].buf.assign((size_t)((combTunes[i % 4] + extra) * scale) + 1, 0.0f);
      combs_[i].pos = 0;
      combs_[i].store = 0.0f;
    }
    for (int i = 0; i < 4; ++i) {
      const int extra = i >= 2 ? 23 : 0;
      allp_[i].buf.assign((size_t)((allpTunes[i % 2] + extra) * scale) + 1, 0.0f);
      allp_[i].pos = 0;
    }
  }

  static float combProcess(Comb& c, float in, float feedback, float damp) {
    const float out = c.buf[c.pos];
    c.store = out * (1.0f - damp) + c.store * damp;
    c.buf[c.pos] = in + c.store * feedback;
    if (++c.pos >= c.buf.size()) c.pos = 0;
    return out;
  }

  static float allpassProcess(Allpass& a, float in) {
    const float bufout = a.buf[a.pos];
    const float out = -in + bufout;
    a.buf[a.pos] = in + bufout * 0.5f;
    if (++a.pos >= a.buf.size()) a.pos = 0;
    return out;
  }

  void reverb(float* l, float* r, int n, float target) {
    const float room = 0.82f + 0.12f * target;
    const float damp = 0.25f;
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      const float in = (l[i] + r[i]) * 0.5f * 0.015f;
      float outL = 0.0f, outR = 0.0f;
      for (int c = 0; c < 4; ++c) outL += combProcess(combs_[c], in, room, damp);
      for (int c = 4; c < 8; ++c) outR += combProcess(combs_[c], in, room, damp);
      outL = allpassProcess(allp_[1], allpassProcess(allp_[0], outL));
      outR = allpassProcess(allp_[3], allpassProcess(allp_[2], outR));
      const float w = wetSmooth_ * 3.0f;
      l[i] = l[i] * (1.0f - 0.35f * wetSmooth_) + outL * w;
      r[i] = r[i] * (1.0f - 0.35f * wetSmooth_) + outR * w;
    }
  }

  // ---- flanger / phaser share an LFO
  std::vector<float> modL_, modR_;
  size_t modPos_ = 0;
  double phase_ = 0.0;

  void flanger(float* l, float* r, int n, float target, double periodSec) {
    const size_t len = modL_.size();
    const double inc = periodSec > 0.01 ? 1.0 / (periodSec * sr_) : 0.0;
    const float minD = 0.0008f * sr_;
    const float maxD = 0.007f * sr_;
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      const float lfo = 0.5f * (1.0f - (float)std::cos(2.0 * kFxPi * phase_));
      const float d = minD + (maxD - minD) * lfo;
      const float rp = (float)modPos_ + (float)len - d;
      const size_t i0 = (size_t)rp % len;
      const size_t i1 = (i0 + 1) % len;
      const float frac = rp - std::floor(rp);
      const float dl = modL_[i0] + (modL_[i1] - modL_[i0]) * frac;
      const float dr = modR_[i0] + (modR_[i1] - modR_[i0]) * frac;
      modL_[modPos_] = l[i] + dl * 0.6f;
      modR_[modPos_] = r[i] + dr * 0.6f;
      l[i] = l[i] * (1.0f - 0.5f * wetSmooth_) + dl * wetSmooth_;
      r[i] = r[i] * (1.0f - 0.5f * wetSmooth_) + dr * wetSmooth_;
      modPos_ = (modPos_ + 1) % len;
      phase_ += inc;
      if (phase_ >= 1.0) phase_ -= 1.0;
    }
  }

  float phZL_[6] = {0, 0, 0, 0, 0, 0};
  float phZR_[6] = {0, 0, 0, 0, 0, 0};
  float phFbL_ = 0.0f, phFbR_ = 0.0f;

  void phaser(float* l, float* r, int n, float target, double periodSec) {
    const double inc = periodSec > 0.01 ? 1.0 / (periodSec * sr_) : 0.0;
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      const float lfo = 0.5f * (1.0f - (float)std::cos(2.0 * kFxPi * phase_));
      const float f = 300.0f + 2200.0f * lfo;
      const float a = (1.0f - std::tan((float)kFxPi * f / sr_)) /
                      (1.0f + std::tan((float)kFxPi * f / sr_));
      float xl = l[i] + phFbL_ * 0.5f;
      float xr = r[i] + phFbR_ * 0.5f;
      for (int s = 0; s < 6; ++s) {
        const float yl = -a * xl + phZL_[s];
        phZL_[s] = xl + a * yl;
        xl = yl;
        const float yr = -a * xr + phZR_[s];
        phZR_[s] = xr + a * yr;
        xr = yr;
      }
      phFbL_ = xl;
      phFbR_ = xr;
      l[i] = l[i] * (1.0f - 0.4f * wetSmooth_) + xl * 0.6f * wetSmooth_;
      r[i] = r[i] * (1.0f - 0.4f * wetSmooth_) + xr * 0.6f * wetSmooth_;
      phase_ += inc;
      if (phase_ >= 1.0) phase_ -= 1.0;
    }
  }

  // ---- bit crusher / sample-rate reducer
  float holdL_ = 0.0f, holdR_ = 0.0f;
  int holdCount_ = 0;

  void crush(float* l, float* r, int n, float target) {
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      const int hold = 1 + (int)(wetSmooth_ * 24.0f);
      const float bits = 16.0f - wetSmooth_ * 11.0f;
      const float q = std::pow(2.0f, bits);
      if (holdCount_ <= 0) {
        holdL_ = std::round(l[i] * q) / q;
        holdR_ = std::round(r[i] * q) / q;
        holdCount_ = hold;
      }
      --holdCount_;
      l[i] = l[i] * (1.0f - wetSmooth_) + holdL_ * wetSmooth_;
      r[i] = r[i] * (1.0f - wetSmooth_) + holdR_ * wetSmooth_;
    }
  }

  // ---- trance gate: chops at the beat division with a soft edge
  void gate(float* l, float* r, int n, float target, double periodSec) {
    const double inc = periodSec > 0.005 ? 1.0 / (periodSec * sr_) : 0.0;
    for (int i = 0; i < n; ++i) {
      wetSmooth_ += (target - wetSmooth_) * 0.002f;
      // Open for the first half of the period, 3 ms ramps.
      const double p = phase_;
      const double edge = 0.003 / std::max(periodSec, 0.005);
      float g;
      if (p < edge) g = (float)(p / edge);
      else if (p < 0.5 - edge) g = 1.0f;
      else if (p < 0.5) g = (float)((0.5 - p) / edge);
      else g = 0.0f;
      const float mix = 1.0f - wetSmooth_ * (1.0f - g);
      l[i] *= mix;
      r[i] *= mix;
      phase_ += inc;
      if (phase_ >= 1.0) phase_ -= 1.0;
    }
  }
};
