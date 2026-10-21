#pragma once
// Offline 4-stem separation (vocals / drums / bass / other) with the Spleeter
// U-Nets exported to ONNX, run through ONNX Runtime. Writes four 16-bit WAV
// files at 44.1 kHz into out_dir. Blocking; call from a worker thread.
#include <atomic>
#include <string>

namespace stems {

struct Progress {
  std::atomic<float> fraction{0.0f};  // 0..1
  std::atomic<bool> cancel{false};
  std::atomic<int> state{0};          // 0 idle, 1 running, 2 done, -1 error
  std::string error;
};

// Returns true on success. Files written: <out_dir>/vocals.wav, drums.wav,
// bass.wav, other.wav. The four stems sum exactly to the (resampled) input.
bool separate(const std::string& inputPath, const std::string& modelPath,
              const std::string& outDir, Progress& progress);

}  // namespace stems
