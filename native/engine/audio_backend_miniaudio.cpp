// TetalDJ: miniaudio implementation unit for the non-Android backends
// (Core Audio on iOS / macOS, ALSA / PulseAudio on Linux). The engine only
// needs the device API, so everything else is compiled out.
#ifndef __ANDROID__
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#include "miniaudio.h"
#endif
