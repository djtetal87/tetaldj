#include "stem_separator.hpp"

#ifdef TETALDJ_NO_ORT
namespace stems {
bool separate(const std::string&, const std::string&, const std::string&, Progress& progress) {
  progress.error = "stems not available on this build";
  progress.state.store(-1);
  return false;
}
}  // namespace stems
#else

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>

#include "dr_mp3.h"
#include "dr_wav.h"
#include "dr_flac.h"
#include <opusfile.h>

#include "dsp/transforms/FFT.h"
#include "onnxruntime_cxx_api.h"
#include "platform_log.hpp"
#include "streaming_decoder.hpp"

namespace stems {
namespace {

constexpr int kSr = 44100;
constexpr int kN = 4096;       // frame length
constexpr int kHop = 1024;     // frame step
constexpr int kF = 1024;       // frequency bins fed to the net
constexpr int kT = 512;        // frames per net call
constexpr int kBins = kN / 2 + 1;
constexpr int kStems = 4;
constexpr double kPi = 3.14159265358979323846;

// ---- 16-bit stereo WAV writer -------------------------------------------
class WavWriter {
 public:
  bool open(const std::string& path, int sr) {
    f_ = std::fopen(path.c_str(), "wb");
    if (!f_) return false;
    sr_ = sr;
    uint8_t h[44] = {0};
    std::fwrite(h, 1, 44, f_);
    return true;
  }
  void write(const float* l, const float* r, size_t n) {
    buf_.resize(n * 2);
    for (size_t i = 0; i < n; ++i) {
      buf_[i * 2] = pcm(l[i]);
      buf_[i * 2 + 1] = pcm(r[i]);
    }
    std::fwrite(buf_.data(), 2, buf_.size(), f_);
    frames_ += n;
  }
  void close() {
    if (!f_) return;
    const uint32_t data = (uint32_t)(frames_ * 4);
    uint8_t h[44] = {0};
    std::memcpy(h, "RIFF", 4);
    put32(h + 4, 36 + data);
    std::memcpy(h + 8, "WAVEfmt ", 8);
    put32(h + 16, 16);
    put16(h + 20, 1);
    put16(h + 22, 2);
    put32(h + 24, (uint32_t)sr_);
    put32(h + 28, (uint32_t)sr_ * 4);
    put16(h + 32, 4);
    put16(h + 34, 16);
    std::memcpy(h + 36, "data", 4);
    put32(h + 40, data);
    std::fseek(f_, 0, SEEK_SET);
    std::fwrite(h, 1, 44, f_);
    std::fclose(f_);
    f_ = nullptr;
  }
  ~WavWriter() { close(); }

 private:
  static int16_t pcm(float v) {
    v = std::max(-1.0f, std::min(1.0f, v));
    return (int16_t)std::lrint(v * 32767.0f);
  }
  static void put16(uint8_t* p, uint16_t v) { p[0] = v & 0xFF; p[1] = v >> 8; }
  static void put32(uint8_t* p, uint32_t v) {
    p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; p[2] = (v >> 16) & 0xFF; p[3] = v >> 24;
  }
  FILE* f_ = nullptr;
  int sr_ = kSr;
  uint64_t frames_ = 0;
  std::vector<int16_t> buf_;
};

// ---- windowed-sinc resampler (any rate -> 44.1 kHz) ----------------------
void resample(const std::vector<float>& in, int inSr, std::vector<float>& out) {
  const size_t inFrames = in.size() / 2;
  if (inSr == kSr) {
    out = in;
    return;
  }
  const double ratio = (double)inSr / (double)kSr;  // input frames per output frame
  const size_t outFrames = (size_t)((double)inFrames / ratio);
  out.assign(outFrames * 2, 0.0f);
  const int taps = 16;
  const double cutoff = std::min(1.0, 1.0 / ratio) * 0.98;  // anti-alias when downsampling
  for (size_t o = 0; o < outFrames; ++o) {
    const double center = (double)o * ratio;
    const long i0 = (long)std::floor(center);
    double accL = 0.0, accR = 0.0, wsum = 0.0;
    for (long i = i0 - taps + 1; i <= i0 + taps; ++i) {
      if (i < 0 || (size_t)i >= inFrames) continue;
      const double x = ((double)i - center) * cutoff;
      const double sinc = x == 0.0 ? 1.0 : std::sin(kPi * x) / (kPi * x);
      const double u = ((double)i - center) / (double)taps;
      if (u <= -1.0 || u >= 1.0) continue;
      const double win = 0.5 * (1.0 + std::cos(kPi * u));
      const double w = sinc * win * cutoff;
      accL += in[(size_t)i * 2] * w;
      accR += in[(size_t)i * 2 + 1] * w;
      wsum += w;
    }
    if (wsum > 1e-9) {
      accL /= wsum;
      accR /= wsum;
    }
    out[o * 2] = (float)accL;
    out[o * 2 + 1] = (float)accR;
  }
}

bool decodeAll(const std::string& path, std::vector<float>& pcm44, Progress& progress) {
  StreamingDecoder dec;
  if (!dec.open(path.c_str()) || dec.totalFrames == 0) return false;
  std::vector<float> native;
  native.reserve((size_t)dec.totalFrames * 2);
  std::vector<float> buf((size_t)65536 * 2);
  dec.seek(0);
  uint64_t pos = 0;
  while (pos < dec.totalFrames) {
    if (progress.cancel.load()) return false;
    const uint64_t got = dec.readStereo(buf.data(), 65536);
    if (got == 0) break;
    native.insert(native.end(), buf.begin(), buf.begin() + (size_t)got * 2);
    pos += got;
  }
  resample(native, (int)dec.sampleRate, pcm44);
  return !pcm44.empty();
}

}  // namespace

bool separate(const std::string& inputPath, const std::string& modelPath,
              const std::string& outDir, Progress& progress) {
  progress.state.store(1);
  progress.fraction.store(0.0f);
  progress.error.clear();
  try {
    std::vector<float> pcm;  // interleaved stereo at 44.1 kHz
    if (!decodeAll(inputPath, pcm, progress)) {
      progress.error = progress.cancel.load() ? "cancelled" : "could not decode the track";
      progress.state.store(-1);
      return false;
    }
    const size_t frames = pcm.size() / 2;
    progress.fraction.store(0.03f);

    // ---- ONNX Runtime session
    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "tetaldj-stems");
    Ort::SessionOptions so;
    so.SetIntraOpNumThreads(2);
    so.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    Ort::Session session(env, modelPath.c_str(), so);
    Ort::AllocatorWithDefaultOptions alloc;
    const char* inNames[1] = {"mag"};
    const char* outNames[kStems] = {"vocals", "drums", "bass", "other"};

    // ---- outputs
    static const char* fileNames[kStems] = {"vocals.wav", "drums.wav", "bass.wav", "other.wav"};
    WavWriter writers[kStems];
    for (int s = 0; s < kStems; ++s) {
      if (!writers[s].open(outDir + "/" + fileNames[s], kSr)) {
        progress.error = "could not write stems to the cache folder";
        progress.state.store(-1);
        return false;
      }
    }

    // ---- STFT setup (centre-padded by N/2 like torch.stft(center=True))
    std::vector<double> window(kN);
    for (int i = 0; i < kN; ++i) window[i] = 0.5 - 0.5 * std::cos(2.0 * kPi * i / kN);  // periodic Hann
    const double olaNorm = 1.5;  // sum of hann^2 at hop N/4
    FFTReal fft(kN);
    const size_t pad = kN / 2;
    const size_t totalFrames = frames / kHop + 1;
    const size_t numBlocks = (totalFrames + kT - 1) / kT;

    std::vector<double> frameIn(kN), re(kN), im(kN), outFrame(kN);
    // Per block spectra: [channel][frame][bin] complex
    std::vector<float> specRe((size_t)2 * kT * kBins), specIm((size_t)2 * kT * kBins);
    std::vector<float> mag((size_t)2 * kT * kF);
    // Overlap-add tails per stem/channel; output is written only once a sample
    // can no longer change (frames beyond it fully added).
    const size_t tail = kN - kHop;
    std::vector<float> ola[kStems][2];
    for (int s = 0; s < kStems; ++s)
      for (int c = 0; c < 2; ++c) ola[s][c].assign((size_t)kT * kHop + tail, 0.0f);
    std::vector<float> outL(kT * kHop), outR(kT * kHop);
    size_t written = 0;  // frames finalised so far (in 44.1k samples)

    auto sample = [&](size_t idx, int ch) -> double {
      if (idx < pad) return 0.0;
      const size_t i = idx - pad;
      return i < frames ? (double)pcm[i * 2 + ch] : 0.0;
    };

    for (size_t b = 0; b < numBlocks; ++b) {
      if (progress.cancel.load()) {
        progress.error = "cancelled";
        progress.state.store(-1);
        return false;
      }
      const size_t f0 = b * kT;
      const int nFrames = (int)std::min((size_t)kT, totalFrames - f0);
      // forward STFT
      for (int c = 0; c < 2; ++c) {
        for (int t = 0; t < kT; ++t) {
          float* sr = &specRe[((size_t)c * kT + t) * kBins];
          float* si = &specIm[((size_t)c * kT + t) * kBins];
          float* sm = &mag[((size_t)c * kT + t) * kF];
          if (t >= nFrames) {
            std::fill(sr, sr + kBins, 0.0f);
            std::fill(si, si + kBins, 0.0f);
            std::fill(sm, sm + kF, 0.0f);
            continue;
          }
          const size_t start = (f0 + t) * kHop;
          for (int i = 0; i < kN; ++i) frameIn[i] = sample(start + i, c) * window[i];
          fft.forward(frameIn.data(), re.data(), im.data());
          for (int k = 0; k < kBins; ++k) {
            sr[k] = (float)re[k];
            si[k] = (float)im[k];
          }
          for (int k = 0; k < kF; ++k) sm[k] = (float)std::sqrt(re[k] * re[k] + im[k] * im[k]);
        }
      }
      // masks from the nets: input (1, 2, T, F)
      const int64_t shape[4] = {1, 2, kT, kF};
      Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
      Ort::Value input = Ort::Value::CreateTensor<float>(mem, mag.data(), mag.size(), shape, 4);
      auto outputs = session.Run(Ort::RunOptions{nullptr}, inNames, &input, 1, outNames, kStems);
      const float* masks[kStems];
      for (int s = 0; s < kStems; ++s) masks[s] = outputs[s].GetTensorData<float>();

      // ratio masks (Spleeter: exponent 2), apply, inverse, overlap-add
      for (int s = 0; s < kStems; ++s) {
        for (int c = 0; c < 2; ++c) {
          float* acc = ola[s][c].data();
          for (int t = 0; t < nFrames; ++t) {
            const size_t m0 = ((size_t)c * kT + t) * kF;
            const float* sr = &specRe[((size_t)c * kT + t) * kBins];
            const float* si = &specIm[((size_t)c * kT + t) * kBins];
            for (int k = 0; k < kBins; ++k) {
              float ratio = 0.0f;
              if (k < kF) {
                const float mi = masks[s][m0 + k];
                float sum = 1e-10f;
                for (int j = 0; j < kStems; ++j) {
                  const float mj = masks[j][m0 + k];
                  sum += mj * mj;
                }
                ratio = (mi * mi + 1e-10f / 2.0f) / sum;
              }
              re[k] = sr[k] * ratio;
              im[k] = si[k] * ratio;
            }
            fft.inverse(re.data(), im.data(), outFrame.data());
            const size_t base = (size_t)t * kHop;
            for (int i = 0; i < kN; ++i) acc[base + i] += (float)(outFrame[i] * window[i] / olaNorm);
          }
        }
      }
      // Samples [0, nFrames*hop) of this block are now final. Add the
      // residual (what the band-limited nets dropped) to "other" so the four
      // stems always sum back to the original.
      const size_t finalN = (size_t)nFrames * kHop;
      for (int c = 0; c < 2; ++c) {
        std::vector<float>& o = ola[3][c];
        for (size_t i = 0; i < finalN; ++i) {
          const size_t idx = f0 * kHop + i;  // padded index
          const double orig = sample(idx, c);
          const float sum = ola[0][c][i] + ola[1][c][i] + ola[2][c][i] + o[i];
          o[i] += (float)orig - sum;
        }
      }
      // write (dropping the centre padding at the very start)
      for (int s = 0; s < kStems; ++s) {
        size_t n = 0;
        for (size_t i = 0; i < finalN; ++i) {
          const size_t idx = f0 * kHop + i;
          if (idx < pad) continue;
          if (idx - pad >= frames) break;
          outL[n] = ola[s][0][i];
          outR[n] = ola[s][1][i];
          ++n;
        }
        writers[s].write(outL.data(), outR.data(), n);
        if (s == 0) written += n;
        // shift the tail down for the next block
        for (int c = 0; c < 2; ++c) {
          std::vector<float>& v = ola[s][c];
          std::copy(v.begin() + finalN, v.end(), v.begin());
          std::fill(v.end() - finalN, v.end(), 0.0f);
        }
      }
      progress.fraction.store(0.03f + 0.96f * (float)(b + 1) / (float)numBlocks);
    }
    // Flush the overlap tail of the last block so the file ends where the
    // track ends.
    if (written < frames) {
      const size_t rest = std::min(frames - written, tail);
      for (int s = 0; s < kStems; ++s) {
        writers[s].write(ola[s][0].data(), ola[s][1].data(), rest);
      }
      written += rest;
    }
    for (int s = 0; s < kStems; ++s) writers[s].close();
    LOGI("stems: wrote %zu frames x 4 to %s", written, outDir.c_str());
    progress.fraction.store(1.0f);
    progress.state.store(2);
    return true;
  } catch (const std::exception& e) {
    progress.error = e.what();
    LOGE("stems failed: %s", e.what());
    progress.state.store(-1);
    return false;
  }
}

}  // namespace stems
#endif  // TETALDJ_NO_ORT
