#pragma once
// Records the stereo master bus to a 16-bit WAV. The audio thread pushes
// frames into a lock-free ring; a writer thread drains it to disk, so the
// callback never touches the file.
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

class MixRecorder {
 public:
  MixRecorder() : ring_((size_t)kRingFrames * 2, 0.0f) {}
  ~MixRecorder() { stop(); }

  bool start(const std::string& path, int sampleRate) {
    stop();
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return false;
    file_ = f;
    sampleRate_ = sampleRate;
    dataBytes_ = 0;
    dropped_.store(0);
    writeHeader();
    head_.store(0);
    tail_.store(0);
    running_.store(true);
    writer_ = std::thread([this] { drain(); });
    return true;
  }

  void stop() {
    if (!running_.load()) return;
    running_.store(false);
    if (writer_.joinable()) writer_.join();
    flushRing();
    finishHeader();
    std::fclose(file_);
    file_ = nullptr;
  }

  bool recording() const { return running_.load(); }
  double seconds() const {
    return sampleRate_ > 0 ? (double)(dataBytes_.load() / 4) / sampleRate_ : 0.0;
  }

  // Audio thread. Interleaved stereo.
  void push(const float* lr, int frames) {
    if (!running_.load(std::memory_order_relaxed)) return;
    const uint64_t head = head_.load(std::memory_order_relaxed);
    const uint64_t tail = tail_.load(std::memory_order_acquire);
    const uint64_t free = (uint64_t)kRingFrames - (head - tail);
    if ((uint64_t)frames > free) {
      dropped_.fetch_add(frames - (int)free);
      frames = (int)free;
    }
    for (int i = 0; i < frames; ++i) {
      const size_t idx = (size_t)((head + i) % kRingFrames) * 2;
      ring_[idx] = lr[i * 2];
      ring_[idx + 1] = lr[i * 2 + 1];
    }
    head_.store(head + frames, std::memory_order_release);
  }

 private:
  static constexpr int kRingFrames = 48000 * 4;  // 4 s at 48 kHz

  void drain() {
    while (running_.load()) {
      if (!flushRing()) std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  }

  bool flushRing() {
    const uint64_t head = head_.load(std::memory_order_acquire);
    uint64_t tail = tail_.load(std::memory_order_relaxed);
    if (head == tail) return false;
    std::vector<int16_t> buf;
    buf.reserve((size_t)(head - tail) * 2);
    while (tail < head) {
      const size_t idx = (size_t)(tail % kRingFrames) * 2;
      buf.push_back(toPcm(ring_[idx]));
      buf.push_back(toPcm(ring_[idx + 1]));
      ++tail;
    }
    tail_.store(tail, std::memory_order_release);
    if (file_) {
      std::fwrite(buf.data(), sizeof(int16_t), buf.size(), file_);
      dataBytes_ += (uint64_t)buf.size() * sizeof(int16_t);
    }
    return true;
  }

  static int16_t toPcm(float v) {
    if (v > 1.0f) v = 1.0f;
    if (v < -1.0f) v = -1.0f;
    return (int16_t)(v * 32767.0f);
  }

  void writeHeader() {
    uint8_t h[44] = {0};
    std::memcpy(h, "RIFF", 4);
    std::memcpy(h + 8, "WAVEfmt ", 8);
    put32(h + 16, 16);
    put16(h + 20, 1);
    put16(h + 22, 2);
    put32(h + 24, (uint32_t)sampleRate_);
    put32(h + 28, (uint32_t)sampleRate_ * 4);
    put16(h + 32, 4);
    put16(h + 34, 16);
    std::memcpy(h + 36, "data", 4);
    std::fwrite(h, 1, 44, file_);
  }

  void finishHeader() {
    if (!file_) return;
    std::fflush(file_);
    uint8_t b[4];
    put32(b, (uint32_t)(36 + dataBytes_.load()));
    std::fseek(file_, 4, SEEK_SET);
    std::fwrite(b, 1, 4, file_);
    put32(b, (uint32_t)dataBytes_.load());
    std::fseek(file_, 40, SEEK_SET);
    std::fwrite(b, 1, 4, file_);
    std::fflush(file_);
  }

  static void put16(uint8_t* p, uint16_t v) { p[0] = v & 0xFF; p[1] = v >> 8; }
  static void put32(uint8_t* p, uint32_t v) {
    p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; p[2] = (v >> 16) & 0xFF; p[3] = v >> 24;
  }

  std::vector<float> ring_;
  std::atomic<uint64_t> head_{0};
  std::atomic<uint64_t> tail_{0};
  std::atomic<bool> running_{false};
  std::atomic<int> dropped_{0};
  std::thread writer_;
  FILE* file_ = nullptr;
  int sampleRate_ = 48000;
  std::atomic<uint64_t> dataBytes_{0};
};
