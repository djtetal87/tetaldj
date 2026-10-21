import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _CreateC = Pointer<Void> Function();
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _StartC = Int32 Function(Pointer<Void>);
typedef _StopC = Void Function(Pointer<Void>);
typedef _SetModeC = Int32 Function(Pointer<Void>, Int32);
typedef _GetIntC = Int32 Function(Pointer<Void>);
typedef _LoadC = Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _LastErrorC = Pointer<Utf8> Function();
typedef _LoadAnalyzedC = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Utf8>,
  Float,
  Int32,
  Float,
);
typedef _UnloadC = Void Function(Pointer<Void>, Int32);
typedef _PlayC = Void Function(Pointer<Void>, Int32, Int32);
typedef _SeekC = Void Function(Pointer<Void>, Int32, Double);
typedef _PosC = Double Function(Pointer<Void>, Int32);
typedef _PlayingC = Int32 Function(Pointer<Void>, Int32);
typedef _SetFloatDeckC = Void Function(Pointer<Void>, Int32, Float);
typedef _SetEqC = Void Function(Pointer<Void>, Int32, Float, Float, Float);
typedef _SetXfaderC = Void Function(Pointer<Void>, Float);
typedef _SetMasterC = Void Function(Pointer<Void>, Float);
typedef _GetBpmC = Float Function(Pointer<Void>, Int32);
typedef _GetKeyC = Int32 Function(Pointer<Void>, Int32);
typedef _NudgeC = Void Function(Pointer<Void>, Int32, Float);
typedef _SetLoopC = Void Function(Pointer<Void>, Int32, Int32, Float);
typedef _BeatJumpC = Void Function(Pointer<Void>, Int32, Int32);
typedef _DeckVoidC = Void Function(Pointer<Void>, Int32);
typedef _SetHotcueC = Void Function(Pointer<Void>, Int32, Int32, Double);
typedef _GetHotcueC = Double Function(Pointer<Void>, Int32, Int32);
typedef _WaveBinsC = Int32 Function();
typedef _RecordStartC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _RecordSecondsC = Double Function(Pointer<Void>);
typedef _StemsSeparateC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _FloatVoidC = Float Function();
typedef _IntVoidC = Int32 Function();
typedef _VoidVoidC = Void Function();
typedef _StemsAttachC = Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _SetStemGainC = Void Function(Pointer<Void>, Int32, Int32, Float);
typedef _SetCueMixC = Void Function(Pointer<Void>, Float, Float);
typedef _SetFxC = Void Function(Pointer<Void>, Int32, Int32, Float, Float);
typedef _WaveCopyC = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Float>,
  Pointer<Float>,
  Int32,
);
typedef _WaveBandsCopyC =
    Int32 Function(
      Pointer<Void>,
      Int32,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Int32,
    );

class NativeEngine {
  NativeEngine._(this._lib, this._handle);

  final DynamicLibrary _lib;
  final Pointer<Void> _handle;
  bool started = false;

  late final _destroy = _lib.lookupFunction<_DestroyC, void Function(Pointer<Void>)>(
    'dj_destroy',
  );
  late final _start = _lib.lookupFunction<_StartC, int Function(Pointer<Void>)>(
    'dj_start',
  );
  late final _stop = _lib.lookupFunction<_StopC, void Function(Pointer<Void>)>(
    'dj_stop',
  );
  late final _setMode = _lib
      .lookupFunction<_SetModeC, int Function(Pointer<Void>, int)>(
        'dj_set_output_mode',
      );
  late final _getChannels = _lib.lookupFunction<_GetIntC, int Function(Pointer<Void>)>(
    'dj_get_output_channels',
  );
  late final _load = _lib
      .lookupFunction<_LoadC, int Function(Pointer<Void>, int, Pointer<Utf8>)>(
        'dj_load',
      );
  late final _lastError = _lib
      .lookupFunction<_LastErrorC, Pointer<Utf8> Function()>('dj_last_error');
  late final _loadAnalyzed = _lib.lookupFunction<
    _LoadAnalyzedC,
    int Function(Pointer<Void>, int, Pointer<Utf8>, double, int, double)
  >('dj_load_with_analysis');
  late final _unload = _lib
      .lookupFunction<_UnloadC, void Function(Pointer<Void>, int)>('dj_unload');
  late final _play = _lib
      .lookupFunction<_PlayC, void Function(Pointer<Void>, int, int)>('dj_play');
  late final _seek = _lib
      .lookupFunction<_SeekC, void Function(Pointer<Void>, int, double)>('dj_seek');
  late final _position = _lib
      .lookupFunction<_PosC, double Function(Pointer<Void>, int)>('dj_position');
  late final _duration = _lib
      .lookupFunction<_PosC, double Function(Pointer<Void>, int)>('dj_duration');
  late final _playing = _lib
      .lookupFunction<_PlayingC, int Function(Pointer<Void>, int)>('dj_playing');
  late final _setGain = _lib
      .lookupFunction<_SetFloatDeckC, void Function(Pointer<Void>, int, double)>(
        'dj_set_gain',
      );
  late final _setEq = _lib
      .lookupFunction<
        _SetEqC,
        void Function(Pointer<Void>, int, double, double, double)
      >('dj_set_eq');
  late final _setFilter = _lib
      .lookupFunction<_SetFloatDeckC, void Function(Pointer<Void>, int, double)>(
        'dj_set_filter',
      );
  late final _setFader = _lib
      .lookupFunction<_SetFloatDeckC, void Function(Pointer<Void>, int, double)>(
        'dj_set_fader',
      );
  late final _setXfader = _lib
      .lookupFunction<_SetXfaderC, void Function(Pointer<Void>, double)>(
        'dj_set_xfader',
      );
  late final _setMaster = _lib
      .lookupFunction<_SetMasterC, void Function(Pointer<Void>, double)>(
        'dj_set_master',
      );
  late final _setRate = _lib
      .lookupFunction<_SetFloatDeckC, void Function(Pointer<Void>, int, double)>(
        'dj_set_rate',
      );
  late final _getBpm = _lib
      .lookupFunction<_GetBpmC, double Function(Pointer<Void>, int)>('dj_get_bpm');
  late final _getKey = _lib
      .lookupFunction<_GetKeyC, int Function(Pointer<Void>, int)>('dj_get_key');
  late final _getBeatOffset = _lib
      .lookupFunction<_GetBpmC, double Function(Pointer<Void>, int)>(
        'dj_get_beat_offset',
      );
  late final _nudgeGrid = _lib
      .lookupFunction<_NudgeC, void Function(Pointer<Void>, int, double)>(
        'dj_nudge_grid',
      );
  late final _setLoop = _lib
      .lookupFunction<_SetLoopC, void Function(Pointer<Void>, int, int, double)>(
        'dj_set_loop',
      );
  late final _loopStart = _lib
      .lookupFunction<_PosC, double Function(Pointer<Void>, int)>('dj_loop_start');
  late final _loopEnd = _lib
      .lookupFunction<_PosC, double Function(Pointer<Void>, int)>('dj_loop_end');
  late final _beatJump = _lib
      .lookupFunction<_BeatJumpC, void Function(Pointer<Void>, int, int)>(
        'dj_beat_jump',
      );
  // Cue / hot cues (TetalDJ): these exist in the C++ engine but upstream
  // SideDeck never bound them.
  late final _setCue = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_set_cue');
  late final _jumpCue = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_jump_cue');
  late final _setCueAt = _lib
      .lookupFunction<_SeekC, void Function(Pointer<Void>, int, double)>(
        'dj_set_cue_at',
      );
  late final _getCue = _lib
      .lookupFunction<_PosC, double Function(Pointer<Void>, int)>('dj_get_cue');
  late final _setHotcue = _lib
      .lookupFunction<_SetHotcueC, void Function(Pointer<Void>, int, int, double)>(
        'dj_set_hotcue',
      );
  late final _jumpHotcue = _lib
      .lookupFunction<_BeatJumpC, void Function(Pointer<Void>, int, int)>(
        'dj_jump_hotcue',
      );
  late final _getHotcue = _lib
      .lookupFunction<_GetHotcueC, double Function(Pointer<Void>, int, int)>(
        'dj_get_hotcue',
      );
  late final _clearHotcue = _lib
      .lookupFunction<_BeatJumpC, void Function(Pointer<Void>, int, int)>(
        'dj_clear_hotcue',
      );
  late final _setKeylock = _lib
      .lookupFunction<_BeatJumpC, void Function(Pointer<Void>, int, int)>(
        'dj_set_keylock',
      );
  late final _recordStart = _lib
      .lookupFunction<_RecordStartC, int Function(Pointer<Void>, Pointer<Utf8>)>(
        'dj_record_start',
      );
  late final _recordStop = _lib
      .lookupFunction<_StopC, void Function(Pointer<Void>)>('dj_record_stop');
  late final _recording = _lib
      .lookupFunction<_GetIntC, int Function(Pointer<Void>)>('dj_recording');
  late final _recordSeconds = _lib
      .lookupFunction<_RecordSecondsC, double Function(Pointer<Void>)>(
        'dj_record_seconds',
      );
  late final _scratchBegin = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_scratch_begin');
  late final _scratchRate = _lib
      .lookupFunction<_SetFloatDeckC, void Function(Pointer<Void>, int, double)>(
        'dj_scratch_rate',
      );
  late final _scratchEnd = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_scratch_end');
  late final _brake = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_brake');
  late final _platterActive = _lib
      .lookupFunction<_PlayingC, int Function(Pointer<Void>, int)>('dj_platter_active');
  late final _stemsAttach = _lib
      .lookupFunction<_StemsAttachC, int Function(Pointer<Void>, int, Pointer<Utf8>)>(
        'dj_stems_attach',
      );
  late final _stemsDetach = _lib
      .lookupFunction<_DeckVoidC, void Function(Pointer<Void>, int)>('dj_stems_detach');
  late final _stemsAttached = _lib
      .lookupFunction<_PlayingC, int Function(Pointer<Void>, int)>('dj_stems_attached');
  late final _setStemGain = _lib
      .lookupFunction<_SetStemGainC, void Function(Pointer<Void>, int, int, double)>(
        'dj_set_stem_gain',
      );
  late final _setPfl = _lib
      .lookupFunction<_BeatJumpC, void Function(Pointer<Void>, int, int)>('dj_set_pfl');
  late final _setCueMix = _lib
      .lookupFunction<_SetCueMixC, void Function(Pointer<Void>, double, double)>('dj_set_cue_mix');
  late final _setFx = _lib
      .lookupFunction<_SetFxC, void Function(Pointer<Void>, int, int, double, double)>(
        'dj_set_fx',
      );
  late final _waveBins = _lib.lookupFunction<_WaveBinsC, int Function()>(
    'dj_waveform_bins',
  );
  late final _waveCopy = _lib
      .lookupFunction<
        _WaveCopyC,
        int Function(
          Pointer<Void>,
          int,
          Pointer<Float>,
          Pointer<Float>,
          int,
        )
      >('dj_waveform_copy');
  late final _waveBandsCopy = _lib
      .lookupFunction<
        _WaveBandsCopyC,
        int Function(
          Pointer<Void>,
          int,
          Pointer<Float>,
          Pointer<Float>,
          Pointer<Float>,
          int,
        )
      >('dj_waveform_bands_copy');

  static DynamicLibrary library() => Platform.isAndroid
      ? DynamicLibrary.open('libdj_engine.so')
      : DynamicLibrary.process();

  static NativeEngine open() {
    final lib = library();
    final create = lib.lookupFunction<_CreateC, _CreateC>('dj_create');
    final handle = create();
    final engine = NativeEngine._(lib, handle);
    engine.started = engine._start(handle) == 1;
    return engine;
  }

  void dispose() {
    _stop(_handle);
    _destroy(_handle);
  }

  bool setExternalMixer(bool enabled) {
    final ok = _setMode(_handle, enabled ? 1 : 0) == 1;
    if (ok) started = true;
    return ok;
  }

  int get outputChannels => _getChannels(_handle);
  int get nativeHandle => _handle.address;

  bool load(
    int deck,
    String path, {
    double? bpm,
    int? key,
    double? beatOffset,
  }) {
    final p = path.toNativeUtf8();
    try {
      if (bpm != null && bpm > 1) {
        return _loadAnalyzed(
              _handle,
              deck,
              p,
              bpm,
              key ?? -1,
              beatOffset ?? 0,
            ) ==
            1;
      }
      return _load(_handle, deck, p) == 1;
    } finally {
      malloc.free(p);
    }
  }

  /// Start writing the master mix to a WAV file. False if it can't open.
  bool recordStart(String path) {
    final p = path.toNativeUtf8();
    try {
      return _recordStart(_handle, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  void recordStop() => _recordStop(_handle);

  /// Vinyl scratch: the deck follows [rate] (1 = forward at normal speed,
  /// negative = backwards) between [scratchBegin] and [scratchEnd].
  void scratchBegin(int deck) => _scratchBegin(_handle, deck);
  void scratchRate(int deck, double rate) => _scratchRate(_handle, deck, rate);
  void scratchEnd(int deck) => _scratchEnd(_handle, deck);

  /// Stop like a turntable motor winding down.
  void brake(int deck) => _brake(_handle, deck);

  /// True while scratching or braking: the playhead moves without playing.
  bool platterActive(int deck) => _platterActive(_handle, deck) != 0;

  /// Play the four stem files in [dir] instead of the loaded file.
  bool stemsAttach(int deck, String dir) {
    final p = dir.toNativeUtf8();
    try {
      return _stemsAttach(_handle, deck, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  void stemsDetach(int deck) => _stemsDetach(_handle, deck);
  bool stemsAttached(int deck) => _stemsAttached(_handle, deck) != 0;
  void setStemGain(int deck, int stem, double gain) =>
      _setStemGain(_handle, deck, stem, gain);

  /// Headphone cue (channels 3-4 on a 4-channel output).
  void setPfl(int deck, bool on) => _setPfl(_handle, deck, on ? 1 : 0);
  void setCueMix(double mix, double gain) => _setCueMix(_handle, mix, gain);
  /// Close and reopen the output (after plugging / unplugging a sound card)
  /// so the channel count is re-detected. Returns whether it restarted.
  bool restartAudio() {
    _stop(_handle);
    return _start(_handle) != 0;
  }

  /// Insert effect: type 0 none, 1 echo, 2 reverb, 3 flanger, 4 phaser,
  /// 5 crush, 6 gate; amount 0..1; beats for the tempo-synced ones.
  void setFx(int deck, int type, double amount, double beats) =>
      _setFx(_handle, deck, type, amount, beats);
  bool get recording => _recording(_handle) != 0;
  double get recordSeconds => _recordSeconds(_handle);

  /// Reason for the last failed [load], or empty if none / success.
  String lastError() {
    final ptr = _lastError();
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  void unload(int deck) => _unload(_handle, deck);
  void play(int deck, bool playing) => _play(_handle, deck, playing ? 1 : 0);
  void seek(int deck, double seconds) => _seek(_handle, deck, seconds);
  double position(int deck) => _position(_handle, deck);
  double duration(int deck) => _duration(_handle, deck);
  bool isPlaying(int deck) => _playing(_handle, deck) == 1;
  void setGain(int deck, double v) => _setGain(_handle, deck, v);
  void setEq(int deck, double low, double mid, double high) =>
      _setEq(_handle, deck, low, mid, high);
  void setFilter(int deck, double amount) => _setFilter(_handle, deck, amount);
  void setFader(int deck, double v) => _setFader(_handle, deck, v);
  void setXfader(double x) => _setXfader(_handle, x);
  void setMaster(double v) => _setMaster(_handle, v);
  void setRate(int deck, double rate) => _setRate(_handle, deck, rate);
  double bpm(int deck) => _getBpm(_handle, deck);
  int key(int deck) => _getKey(_handle, deck);
  double beatOffset(int deck) => _getBeatOffset(_handle, deck);
  void nudgeGrid(int deck, double seconds) => _nudgeGrid(_handle, deck, seconds);
  void setLoop(int deck, bool enabled, double bars) =>
      _setLoop(_handle, deck, enabled ? 1 : 0, bars);
  double loopStart(int deck) => _loopStart(_handle, deck);
  double loopEnd(int deck) => _loopEnd(_handle, deck);
  void beatJump(int deck, int beats) => _beatJump(_handle, deck, beats);

  /// Set the main cue point at the current playhead.
  void setCue(int deck) => _setCue(_handle, deck);

  /// Jump the playhead back to the main cue point.
  void jumpCue(int deck) => _jumpCue(_handle, deck);

  /// Set the main cue point at an absolute position in seconds.
  void setCueAt(int deck, double seconds) => _setCueAt(_handle, deck, seconds);

  /// Current main cue point in seconds.
  double cue(int deck) => _getCue(_handle, deck);

  /// Store hot cue [index] (0..3). A negative [seconds] means "at playhead".
  void setHotcue(int deck, int index, double seconds) =>
      _setHotcue(_handle, deck, index, seconds);

  void jumpHotcue(int deck, int index) => _jumpHotcue(_handle, deck, index);

  /// Position of hot cue [index] in seconds, or a negative value if unset.
  double hotcue(int deck, int index) => _getHotcue(_handle, deck, index);

  void clearHotcue(int deck, int index) => _clearHotcue(_handle, deck, index);

  /// Keep the pitch when the tempo changes (master tempo).
  void setKeylock(int deck, bool enabled) =>
      _setKeylock(_handle, deck, enabled ? 1 : 0);

  ({Float32List min, Float32List max}) waveform(int deck) {
    final bins = _waveBins();
    final minPtr = malloc<Float>(bins);
    final maxPtr = malloc<Float>(bins);
    try {
      final n = _waveCopy(_handle, deck, minPtr, maxPtr, bins);
      return (
        min: Float32List.fromList(minPtr.asTypedList(n)),
        max: Float32List.fromList(maxPtr.asTypedList(n)),
      );
    } finally {
      malloc.free(minPtr);
      malloc.free(maxPtr);
    }
  }

  /// Per-bin low / mid / high energy (0..1) for the three-colour waveform.
  ({Float32List low, Float32List mid, Float32List high}) waveformBands(int deck) {
    final bins = _waveBins();
    final lowPtr = malloc<Float>(bins);
    final midPtr = malloc<Float>(bins);
    final highPtr = malloc<Float>(bins);
    try {
      final n = _waveBandsCopy(_handle, deck, lowPtr, midPtr, highPtr, bins);
      return (
        low: Float32List.fromList(lowPtr.asTypedList(n)),
        mid: Float32List.fromList(midPtr.asTypedList(n)),
        high: Float32List.fromList(highPtr.asTypedList(n)),
      );
    } finally {
      malloc.free(lowPtr);
      malloc.free(midPtr);
      malloc.free(highPtr);
    }
  }
}

/// Stem separation runs on the engine library but needs no engine handle, so
/// it can run in a worker isolate. Progress is global (one job at a time).
class StemsNative {
  StemsNative._() : _lib = NativeEngine.library();
  static final instance = StemsNative._();
  final DynamicLibrary _lib;

  late final _separate = _lib
      .lookupFunction<_StemsSeparateC, int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>(
        'dj_stems_separate',
      );
  late final _progress = _lib.lookupFunction<_FloatVoidC, double Function()>('dj_stems_progress');
  late final _state = _lib.lookupFunction<_IntVoidC, int Function()>('dj_stems_state');
  late final _cancel = _lib.lookupFunction<_VoidVoidC, void Function()>('dj_stems_cancel');
  late final _error = _lib.lookupFunction<_LastErrorC, Pointer<Utf8> Function()>('dj_stems_error');

  /// Blocking: decode, separate and write vocals/drums/bass/other WAVs.
  bool separate(String input, String model, String outDir) {
    final a = input.toNativeUtf8();
    final b = model.toNativeUtf8();
    final c = outDir.toNativeUtf8();
    try {
      return _separate(a, b, c) != 0;
    } finally {
      malloc.free(a);
      malloc.free(b);
      malloc.free(c);
    }
  }

  double get progress => _progress();
  /// 0 idle, 1 running, 2 done, -1 error.
  int get state => _state();
  void cancel() => _cancel();
  String get error {
    final p = _error();
    return p == nullptr ? '' : p.toDartString();
  }
}

/// Entry point for Isolate.run: separation in a worker so the UI keeps going.
bool runStemSeparation(List<String> args) =>
    StemsNative.instance.separate(args[0], args[1], args[2]);
