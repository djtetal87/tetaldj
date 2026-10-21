// TetalDJ: miniaudio implementation unit for the non-Android backends
// (Core Audio on iOS / macOS, ALSA / PulseAudio on Linux). The engine only
// needs the device API, so everything else is compiled out.
#ifdef __APPLE__
#include <TargetConditionals.h>
#endif
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

// ---- output route (iOS) ----------------------------------------------------
// With a controller's sound card plugged in, iOS sends everything to it.
// "Phone" forces the built-in speaker instead (needs the PlayAndRecord
// session category, which the engine's context asks for on iOS).
#if defined(__APPLE__) && TARGET_OS_IPHONE
#import <AVFoundation/AVFoundation.h>
extern "C" void tetaldj_prefer_low_latency(void) {
  // 256 frames at 48 kHz ≈ 5 ms; iOS honours it when the hardware can.
  AVAudioSession* s = [AVAudioSession sharedInstance];
  [s setPreferredIOBufferDuration:0.005 error:nil];
  [s setPreferredSampleRate:48000 error:nil];
}
extern "C" int tetaldj_force_speaker(int on) {
  NSError* err = nil;
  AVAudioSession* s = [AVAudioSession sharedInstance];
  BOOL ok = [s overrideOutputAudioPort:(on ? AVAudioSessionPortOverrideSpeaker
                                           : AVAudioSessionPortOverrideNone)
                                 error:&err];
  return ok ? 1 : 0;
}
extern "C" int tetaldj_output_is_usb(void) {
  for (AVAudioSessionPortDescription* p in [AVAudioSession sharedInstance].currentRoute.outputs) {
    if ([p.portType isEqualToString:AVAudioSessionPortUSBAudio]) return 1;
  }
  return 0;
}
#else
extern "C" void tetaldj_prefer_low_latency(void) {}
extern "C" int tetaldj_force_speaker(int) { return 0; }
extern "C" int tetaldj_output_is_usb(void) { return 0; }
#endif
