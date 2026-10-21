#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void* DjEngine;

DjEngine dj_create(void);
void dj_destroy(DjEngine engine);

int dj_start(DjEngine engine);
void dj_stop(DjEngine engine);

/** Output mode: 0 = internal stereo (phone), 1 = external 4ch USB (deck A 1-2, B 3-4).
 *  In mode 1 Oboe is stopped and the Java USB AudioTrack is the sink, so USB
 *  device selection happens on the Java side, not here. */
int dj_set_output_mode(DjEngine engine, int mode);
int dj_get_output_mode(DjEngine engine);
int dj_get_output_channels(DjEngine engine);

int dj_load(DjEngine engine, int deck, const char* path);
void dj_unload(DjEngine engine, int deck);

void dj_play(DjEngine engine, int deck, int playing);
void dj_seek(DjEngine engine, int deck, double seconds);
void dj_set_cue(DjEngine engine, int deck);
void dj_jump_cue(DjEngine engine, int deck);
void dj_set_cue_at(DjEngine engine, int deck, double seconds);
double dj_get_cue(DjEngine engine, int deck);

double dj_position(DjEngine engine, int deck);
double dj_duration(DjEngine engine, int deck);
int dj_playing(DjEngine engine, int deck);
int dj_loaded(DjEngine engine, int deck);

void dj_set_gain(DjEngine engine, int deck, float linear);
void dj_set_eq(DjEngine engine, int deck, float low_db, float mid_db, float high_db);
void dj_set_filter(DjEngine engine, int deck, float amount);
void dj_set_fader(DjEngine engine, int deck, float linear);
void dj_set_xfader(DjEngine engine, float x);
void dj_set_master(DjEngine engine, float linear);
void dj_set_rate(DjEngine engine, int deck, float rate);
void dj_set_keylock(DjEngine engine, int deck, int enabled);

float dj_get_bpm(DjEngine engine, int deck);
int dj_get_key(DjEngine engine, int deck);
float dj_get_beat_offset(DjEngine engine, int deck);
void dj_nudge_grid(DjEngine engine, int deck, float seconds);

void dj_set_loop(DjEngine engine, int deck, int enabled, float bars);
double dj_loop_start(DjEngine engine, int deck);
double dj_loop_end(DjEngine engine, int deck);
void dj_set_hotcue(DjEngine engine, int deck, int index, double seconds);
void dj_jump_hotcue(DjEngine engine, int deck, int index);
double dj_get_hotcue(DjEngine engine, int deck, int index);
void dj_clear_hotcue(DjEngine engine, int deck, int index);
void dj_beat_jump(DjEngine engine, int deck, int beats);

int dj_waveform_bins(void);
int dj_waveform_copy(DjEngine engine, int deck, float* min_out, float* max_out, int bins);
/// Per-bin RMS of <200 Hz, 200 Hz-2 kHz and >2 kHz, normalised 0..1 (3-colour waveform).
int dj_waveform_bands_copy(DjEngine engine, int deck, float* low_out, float* mid_out, float* high_out, int bins);

/** Decode a 60s prefix (22 kHz mono) + BPM/key/grid. Uses ID3 TBPM/TKEY when present. */
int dj_analyze_file(const char* path, float* bpm, int* key, float* beat_offset);

/** Length in seconds from the file header / decoder. Does not decode PCM. */
double dj_file_duration(const char* path);

/** Load PCM and apply previously cached analysis (skips BPM/key). bpm<=0 runs a full analyze. */
int dj_load_with_analysis(DjEngine engine, int deck, const char* path, float bpm, int key,
                          float beat_offset);

/** Null-terminated reason for the last failed dj_load / open, or "". */
const char* dj_last_error(void);

/// Insert effect per deck: type 0 none, 1 echo, 2 reverb, 3 flanger, 4 phaser,
/// 5 crush, 6 gate; amount 0..1 (wet / intensity); beats = length for the
/// tempo-synced ones (echo time, LFO period, gate period).
void dj_set_fx(DjEngine engine, int deck, int type, float amount, float beats);

/// Vinyl scratch: between begin and end the deck follows [rate] (1 = normal
/// speed forward, negative = backwards) instead of playing.
void dj_scratch_begin(DjEngine engine, int deck);
void dj_scratch_rate(DjEngine engine, int deck, float rate);
void dj_scratch_end(DjEngine engine, int deck);
/// Stop like a turntable motor: the deck winds down over ~0.8 s.
void dj_brake(DjEngine engine, int deck);
/// 1 while the deck is scratching or braking (the playhead still moves).
int dj_platter_active(DjEngine engine, int deck);

/// Record the stereo master mix to a 16-bit WAV at [path]. Returns 1 on success.
int dj_record_start(DjEngine engine, const char* path);
void dj_record_stop(DjEngine engine);
int dj_recording(DjEngine engine);
double dj_record_seconds(DjEngine engine);

#ifdef __cplusplus
}
#endif
