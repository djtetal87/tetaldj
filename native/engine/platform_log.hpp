#pragma once

// TetalDJ: one logging macro for every platform. Android goes to logcat
// (as upstream SideDeck did); iOS / macOS / Linux go to stderr, which Xcode
// and the terminal both show.

#ifdef __ANDROID__
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "tetaldj", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "tetaldj", __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...)                              \
  do {                                         \
    std::fprintf(stderr, "[tetaldj] " __VA_ARGS__); \
    std::fputc('\n', stderr);                  \
  } while (0)
#define LOGE(...)                              \
  do {                                         \
    std::fprintf(stderr, "[tetaldj:E] " __VA_ARGS__); \
    std::fputc('\n', stderr);                  \
  } while (0)
#endif
