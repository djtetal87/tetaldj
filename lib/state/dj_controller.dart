import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sidedeck/engine/analysis_cache.dart';
import 'package:sidedeck/engine/hotcue_store.dart';
import 'package:sidedeck/engine/native_engine.dart';
import 'package:sidedeck/engine/track_analyzer.dart';
import 'package:sidedeck/engine/usb_output.dart';

class DeckState {
  String? path;
  String title = 'Empty';
  String artist = '';
  bool loaded = false;
  bool playing = false;
  bool loopEnabled = false;
  double loopBars = 1;
  double loopStart = 0;
  double loopEnd = 0;
  double position = 0;
  double duration = 0;
  double bpm = 0;
  int key = -1;
  double rate = 1;
  bool synced = false;
  bool keylock = true;
  double beatOffset = 0;
  double gain = 1;
  double fader = 1;
  double filter = 0;
  double eqLow = 0;
  double eqMid = 0;
  double eqHigh = 0;

  /// Main cue point in seconds (0 = start of track until the DJ sets one).
  double cuePoint = 0;

  /// Hot cue positions in seconds; a negative value means the slot is empty.
  final List<double> hotcues = List<double>.filled(HotCueStore.slots, -1);
  Float32List waveMin = Float32List(0);
  Float32List waveMax = Float32List(0);
  Float32List waveLow = Float32List(0);
  Float32List waveMid = Float32List(0);
  Float32List waveHigh = Float32List(0);
}

class DjController extends ChangeNotifier {
  DjController() {
    _engine = NativeEngine.open();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    if (!_engine.started) {
      engineError = 'Audio engine failed to start.';
    }
    if (Platform.isAndroid) {
      _usbSub = UsbOutput.events().listen(_onUsbEvent);
    }
  }

  late final NativeEngine _engine;
  late final Timer _ticker;
  StreamSubscription<UsbHotplugEvent>? _usbSub;
  final AnalysisCache _analysisCache = AnalysisCache.instance;
  final HotCueStore _cueStore = HotCueStore.instance;
  final Set<int> _declinedMixerIds = {};

  final DeckState deckA = DeckState();
  final DeckState deckB = DeckState();
  double xfader = 0.5;
  double master = 1.0;
  bool externalMixer = false;
  String usbDeviceName = '';
  int usbDeviceId = 0;
  UsbMixerOffer? mixerOffer;
  String? engineError;

  /// Mix recording: file being written and elapsed seconds (null = idle).
  String? recordingPath;
  double recordingSeconds = 0;
  int? loadingDeck;
  String? loadingTitle;
  String? loadingPath;

  DeckState deck(int i) => i == 0 ? deckA : deckB;

  void clearError() {
    engineError = null;
    notifyListeners();
  }

  void _onUsbEvent(UsbHotplugEvent event) {
    if (event.attached) {
      _onUsbAttached(event);
    } else {
      _onUsbDetached(event);
    }
  }

  void _onUsbAttached(UsbHotplugEvent event) {
    if (externalMixer) return;
    if (_declinedMixerIds.contains(event.id)) return;
    if (mixerOffer?.id == event.id) return;
    mixerOffer = UsbMixerOffer(
      id: event.id,
      channels: event.channels,
      name: event.name,
    );
    notifyListeners();
  }

  void _onUsbDetached(UsbHotplugEvent event) {
    _declinedMixerIds.remove(event.id);
    final offeringThis = mixerOffer?.id == event.id;
    if (offeringThis) mixerOffer = null;
    if (externalMixer && usbDeviceId == event.id) {
      final name = UsbOutput.deviceLabel(
        usbDeviceName.isEmpty ? event.name : usbDeviceName,
      );
      setExternalMixer(false).then((_) {
        engineError = '$name disconnected; audio is back on the phone.';
        notifyListeners();
      });
      return;
    }
    if (offeringThis) notifyListeners();
  }

  Future<void> acceptMixerOffer() async {
    mixerOffer = null;
    notifyListeners();
    await setExternalMixer(true);
  }

  void declineMixerOffer() {
    final id = mixerOffer?.id;
    if (id != null) _declinedMixerIds.add(id);
    mixerOffer = null;
    notifyListeners();
  }

  void _tick() {
    if (recordingPath != null) recordingSeconds = _engine.recordSeconds;
    var dirty = false;
    for (var i = 0; i < 2; i++) {
      final d = deck(i);
      if (!d.loaded || !d.playing) continue;
      d.position = _engine.position(i);
      d.playing = _engine.isPlaying(i);
      if (d.loopEnabled) {
        _readLoop(i);
      }
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  Future<bool> loadFile(
    int deckIndex,
    String path, {
    String? title,
    String? artist,
  }) async {
    loadingDeck = deckIndex;
    loadingTitle = title ?? path.split(RegExp(r'[\\/]')).last;
    loadingPath = path;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 16));

    TrackAnalysis? cached;
    try {
      final stat = await File(path).stat();
      cached = await _analysisCache.get(
        path,
        stat.size,
        stat.modified.millisecondsSinceEpoch,
      );
    } catch (_) {}

    final ok = _engine.load(
      deckIndex,
      path,
      bpm: cached?.bpm,
      key: cached?.key,
      beatOffset: cached?.beatOffset,
    );
    final d = deck(deckIndex);
    if (!ok) {
      loadingDeck = null;
      loadingTitle = null;
      loadingPath = null;
      final name = title ?? path.split(RegExp(r'[\\/]')).last;
      final detail = _engine.lastError();
      engineError = detail.isNotEmpty
          ? 'Could not load $name - $detail'
          : 'Could not decode $name (need MP3, WAV, FLAC, Opus, or AAC M4A).';
      notifyListeners();
      return false;
    }
    d.path = path;
    d.title = title ?? path.split(RegExp(r'[\\/]')).last;
    d.artist = artist ?? '';
    d.loaded = true;
    d.playing = false;
    d.position = 0;
    d.duration = _engine.duration(deckIndex);
    d.bpm = _engine.bpm(deckIndex);
    d.key = _engine.key(deckIndex);
    d.beatOffset = _engine.beatOffset(deckIndex);
    d.rate = 1;
    d.synced = false;
    d.loopEnabled = false;
    d.loopStart = 0;
    d.loopEnd = 0;
    // The engine resets cues on load; restore the ones saved for this track.
    d.cuePoint = 0;
    for (var i = 0; i < HotCueStore.slots; i++) {
      d.hotcues[i] = -1;
    }
    final savedCues = await _cueStore.load(path);
    savedCues.forEach((slot, seconds) {
      if (slot < 0) {
        d.cuePoint = seconds;
        _engine.setCueAt(deckIndex, seconds);
      } else if (slot < HotCueStore.slots) {
        d.hotcues[slot] = seconds;
        _engine.setHotcue(deckIndex, slot, seconds);
      }
    });
    final wave = _engine.waveform(deckIndex);
    d.waveMin = wave.min;
    d.waveMax = wave.max;
    final bands = _engine.waveformBands(deckIndex);
    d.waveLow = bands.low;
    d.waveMid = bands.mid;
    d.waveHigh = bands.high;
    _engine.setRate(deckIndex, 1);
    _engine.setKeylock(deckIndex, d.keylock);
    _nudgeBend[deckIndex] = 0;
    _engine.setGain(deckIndex, d.gain);
    _engine.setFader(deckIndex, d.fader);
    _engine.setFilter(deckIndex, d.filter);
    _engine.setEq(deckIndex, d.eqLow, d.eqMid, d.eqHigh);

    if (cached == null) {
      try {
        final file = File(path);
        final stat = await file.stat();
        await _analysisCache.put(
          path: path,
          size: stat.size,
          mtime: stat.modified.millisecondsSinceEpoch,
          bpm: d.bpm,
          key: d.key,
          beatOffset: d.beatOffset,
        );
      } catch (_) {}
    }

    loadingDeck = null;
    loadingTitle = null;
    loadingPath = null;
    _followMasterBpm(deckIndex);
    notifyListeners();
    return true;
  }

  /// Re-read a track that was just re-analyzed, so a deck holding it picks up
  /// the new BPM and beat grid instead of keeping the stale one.
  Future<void> reloadIfLoaded(
    String path, {
    String? title,
    String? artist,
  }) async {
    for (var i = 0; i < 2; i++) {
      final d = deck(i);
      if (d.path != path) continue;
      await loadFile(
        i,
        path,
        title: title ?? d.title,
        artist: artist ?? d.artist,
      );
    }
  }

  void playPause(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    final next = !d.playing;
    _engine.play(deckIndex, next);
    d.playing = next;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cue & hot cues (TetalDJ)
  // ---------------------------------------------------------------------------

  /// Main CUE button, Serato/VDJ style:
  /// - paused  → set the cue point at the playhead;
  /// - playing → jump back to the cue point and pause.
  void cue(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    if (d.playing) {
      _engine.play(deckIndex, false);
      d.playing = false;
      _engine.jumpCue(deckIndex);
    } else {
      _engine.setCue(deckIndex);
      d.cuePoint = _engine.cue(deckIndex);
      final path = d.path;
      if (path != null) _cueStore.set(path, -1, d.cuePoint);
    }
    d.position = _engine.position(deckIndex);
    _readLoop(deckIndex);
    notifyListeners();
  }

  /// Play from the cue point (classic "cue + play"): jump and start.
  void cuePlay(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    _engine.jumpCue(deckIndex);
    _engine.play(deckIndex, true);
    d.playing = true;
    d.position = _engine.position(deckIndex);
    _readLoop(deckIndex);
    notifyListeners();
  }

  bool hasHotcue(int deckIndex, int slot) => deck(deckIndex).hotcues[slot] >= 0;

  /// Hot cue pad tap: empty slot → store the playhead; set slot → jump there.
  /// Jumping while paused also starts playback, like a real controller.
  void hotcue(int deckIndex, int slot) {
    final d = deck(deckIndex);
    if (!d.loaded || slot < 0 || slot >= HotCueStore.slots) return;
    if (d.hotcues[slot] < 0) {
      _engine.setHotcue(deckIndex, slot, -1);
      d.hotcues[slot] = _engine.hotcue(deckIndex, slot);
      final path = d.path;
      if (path != null) _cueStore.set(path, slot, d.hotcues[slot]);
    } else {
      _engine.jumpHotcue(deckIndex, slot);
      if (!d.playing) {
        _engine.play(deckIndex, true);
        d.playing = true;
      }
    }
    d.position = _engine.position(deckIndex);
    _readLoop(deckIndex);
    notifyListeners();
  }

  /// Long press on a pad: clear that hot cue.
  void clearHotcue(int deckIndex, int slot) {
    final d = deck(deckIndex);
    if (!d.loaded || slot < 0 || slot >= HotCueStore.slots) return;
    _engine.clearHotcue(deckIndex, slot);
    d.hotcues[slot] = -1;
    final path = d.path;
    if (path != null) _cueStore.clear(path, slot);
    notifyListeners();
  }

  /// Waveform tap: jump exactly 4 beats toward the tap. No grid snap —
  /// integer beat jumps keep relative phase.
  void seek(int deckIndex, double seconds) {
    final d = deck(deckIndex);
    if (!d.loaded) return;

    final target = seconds.clamp(0.0, math.max(0.0, d.duration)).toDouble();
    if (d.bpm > 1) {
      final dir = target.compareTo(d.position);
      if (dir == 0) return;
      _engine.beatJump(deckIndex, dir * 4);
      d.position = _engine.position(deckIndex);
      _readLoop(deckIndex);
      notifyListeners();
      return;
    }

    seekTo(deckIndex, target);
  }

  /// Absolute seek (overview scrub / pause nudge). Ignores beat-jump mode.
  void seekTo(int deckIndex, double seconds) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    final target = seconds.clamp(0.0, math.max(0.0, d.duration)).toDouble();
    _engine.seek(deckIndex, target);
    d.position = target;
    _readLoop(deckIndex);
    notifyListeners();
  }

  void setGain(int deckIndex, double v) {
    deck(deckIndex).gain = v;
    _engine.setGain(deckIndex, v);
    notifyListeners();
  }

  void setFader(int deckIndex, double v) {
    deck(deckIndex).fader = v;
    _engine.setFader(deckIndex, v);
    notifyListeners();
  }

  void setEq(int deckIndex, {double? low, double? mid, double? high}) {
    final d = deck(deckIndex);
    d.eqLow = low ?? d.eqLow;
    d.eqMid = mid ?? d.eqMid;
    d.eqHigh = high ?? d.eqHigh;
    _engine.setEq(deckIndex, d.eqLow, d.eqMid, d.eqHigh);
    notifyListeners();
  }

  void setFilter(int deckIndex, double amount) {
    deck(deckIndex).filter = amount;
    _engine.setFilter(deckIndex, amount);
    notifyListeners();
  }

  void setXfader(double x) {
    xfader = x;
    _engine.setXfader(x);
    notifyListeners();
  }

  void setMaster(double v) {
    master = v;
    _engine.setMaster(v);
    notifyListeners();
  }

  void setRate(int deckIndex, double rate) {
    final d = deck(deckIndex);
    d.rate = rate;
    d.synced = false;
    _applyRate(deckIndex);
    _followMasterBpm(deckIndex);
    notifyListeners();
  }

  /// Start recording the mix into `<Documents>/Grabaciones/`.
  Future<String?> startRecording() async {
    if (recordingPath != null) return recordingPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'Grabaciones'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'TetalDJ ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}.${two(now.minute)}.wav';
      final path = p.join(dir.path, name);
      if (!_engine.recordStart(path)) {
        engineError = 'No se pudo crear la grabación.';
        notifyListeners();
        return null;
      }
      recordingPath = path;
      recordingSeconds = 0;
      notifyListeners();
      return path;
    } catch (e) {
      engineError = 'No se pudo grabar: $e';
      notifyListeners();
      return null;
    }
  }

  String? stopRecording() {
    if (recordingPath == null) return null;
    _engine.recordStop();
    final path = recordingPath;
    recordingPath = null;
    notifyListeners();
    return path;
  }

  void setKeylock(int deckIndex, bool enabled) {
    final d = deck(deckIndex);
    d.keylock = enabled;
    _engine.setKeylock(deckIndex, enabled);
    notifyListeners();
  }

  /// Vinyl-style platter touch: hold pauses the audio, drag scrubs, release
  /// resumes if it was playing.
  final List<bool> _platterResume = [false, false];

  void platterTouch(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    _platterResume[deckIndex] = d.playing;
    if (d.playing) {
      _engine.play(deckIndex, false);
      d.playing = false;
      notifyListeners();
    }
  }

  void platterRelease(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    if (_platterResume[deckIndex]) {
      _platterResume[deckIndex] = false;
      _engine.play(deckIndex, true);
      d.playing = true;
      notifyListeners();
    }
  }

  final List<double> _nudgeBend = [0, 0]; // temporary pitch bend while held
  final List<Timer?> _nudgeHold = [null, null];

  void _applyRate(int deckIndex) {
    final d = deck(deckIndex);
    final effective = (d.rate * (1.0 + _nudgeBend[deckIndex])).clamp(0.5, 2.0);
    _engine.setRate(deckIndex, effective);
  }

  /// ±0.1 BPM (heard tempo). Rate is derived from the track's original BPM.
  void nudgeBpm(int deckIndex, double delta) {
    final d = deck(deckIndex);
    if (!d.loaded || d.bpm <= 0) return;
    final heard = d.bpm * d.rate;
    final tenths = (heard * 10).round() + (delta * 10).round();
    final next = (tenths / 10.0).clamp(d.bpm * 0.5, d.bpm * 2.0);
    d.rate = next / d.bpm;
    d.synced = false;
    _applyRate(deckIndex);
    _followMasterBpm(deckIndex);
    notifyListeners();
  }

  /// Hold to briefly speed up (+) or slow down (−) for beatmatching.
  /// While paused, the same buttons jog the playhead so you can cue visually.
  void startNudge(int deckIndex, {required bool faster}) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    _nudgeHold[deckIndex]?.cancel();
    if (d.playing) {
      _nudgeBend[deckIndex] = faster ? 0.08 : -0.08;
      _applyRate(deckIndex);
      notifyListeners();
      return;
    }
    _jogPaused(deckIndex, faster: faster);
    _nudgeHold[deckIndex] = Timer(const Duration(milliseconds: 350), () {
      _nudgeHold[deckIndex] = Timer.periodic(const Duration(milliseconds: 50), (
        _,
      ) {
        if (!deck(deckIndex).playing) {
          _jogPaused(deckIndex, faster: faster);
        }
      });
    });
  }

  void endNudge(int deckIndex) {
    _nudgeHold[deckIndex]?.cancel();
    _nudgeHold[deckIndex] = null;
    _nudgeBend[deckIndex] = 0;
    _applyRate(deckIndex);
    notifyListeners();
  }

  void _jogPaused(int deckIndex, {required bool faster}) {
    final d = deck(deckIndex);
    if (!d.loaded || d.playing) return;
    const step = 0.04; // 40 ms — visible on the 8 s zoom window, still fine
    final t = (d.position + (faster ? step : -step))
        .clamp(0.0, math.max(0.0, d.duration))
        .toDouble();
    _engine.seek(deckIndex, t);
    d.position = t;
    notifyListeners();
  }

  void setLoop(int deckIndex, bool enabled, [double? bars]) {
    final d = deck(deckIndex);
    if (bars != null) d.loopBars = bars.clamp(0.0625, 8.0);
    d.loopEnabled = enabled;
    _engine.setLoop(deckIndex, enabled, d.loopBars);
    _readLoop(deckIndex);
    notifyListeners();
  }

  static const loopBeats = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];

  void halfLoop(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    final beats = d.loopBars * 4;
    final i = loopBeats.indexWhere((b) => (b - beats).abs() < 0.05);
    final next = i <= 0 ? loopBeats.first : loopBeats[i - 1];
    setLoop(deckIndex, d.loopEnabled, next / 4.0);
  }

  void doubleLoop(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loaded) return;
    final beats = d.loopBars * 4;
    var i = loopBeats.indexWhere((b) => (b - beats).abs() < 0.05);
    if (i < 0) i = 0;
    final next = i >= loopBeats.length - 1 ? loopBeats.last : loopBeats[i + 1];
    setLoop(deckIndex, d.loopEnabled, next / 4.0);
  }

  void _readLoop(int deckIndex) {
    final d = deck(deckIndex);
    if (!d.loopEnabled) {
      d.loopStart = 0;
      d.loopEnd = 0;
      return;
    }
    d.loopStart = _engine.loopStart(deckIndex);
    d.loopEnd = _engine.loopEnd(deckIndex);
  }

  void beatJump(int deckIndex, int beats) {
    _engine.beatJump(deckIndex, beats);
    deck(deckIndex).position = _engine.position(deckIndex);
    _readLoop(deckIndex);
    notifyListeners();
  }

  /// Match [slave] tempo to the other deck and keep following its BPM.
  /// Does not move the playhead. Press SYNC on the deck you want to change.
  void sync(int slave) {
    final masterIdx = 1 - slave;
    if (!deck(slave).loaded || !deck(masterIdx).loaded) return;
    _nudgeBend[slave] = 0;
    deck(slave).synced = true;
    deck(masterIdx).synced = false;
    _applySlaveTempo(slave);
    notifyListeners();
  }

  double _tempoMatchRate(DeckState slave, DeckState master) {
    final slaveBpm = slave.bpm <= 0 ? 1.0 : slave.bpm;
    return (master.bpm * master.rate / slaveBpm).clamp(0.5, 2.0);
  }

  void _applySlaveTempo(int slave) {
    final d = deck(slave);
    final master = deck(1 - slave);
    if (!d.loaded || !master.loaded) return;
    d.rate = _tempoMatchRate(d, master);
    _applyRate(slave);
  }

  /// If [deckIndex] is the master of a synced slave, keep that slave matched.
  void _followMasterBpm(int deckIndex) {
    final slave = 1 - deckIndex;
    if (!deck(slave).synced) return;
    _applySlaveTempo(slave);
  }

  void nudgeGrid(int deckIndex, double seconds) {
    _engine.nudgeGrid(deckIndex, seconds);
    final d = deck(deckIndex);
    d.beatOffset = _engine.beatOffset(deckIndex);
    notifyListeners();
    _persistAnalysis(d);
  }

  /// Shift the painted grid. Negative = earlier (yellow moves left).
  void shiftGridBeats(int deckIndex, int beats) {
    final d = deck(deckIndex);
    if (!d.loaded || d.bpm <= 1) return;
    nudgeGrid(deckIndex, beats * (60.0 / d.bpm));
  }

  void shiftGridMs(int deckIndex, int milliseconds) {
    if (!deck(deckIndex).loaded) return;
    nudgeGrid(deckIndex, milliseconds / 1000.0);
  }

  Future<void> _persistAnalysis(DeckState d) async {
    final path = d.path;
    if (path == null || path.isEmpty || d.bpm <= 0) return;
    try {
      final stat = await File(path).stat();
      await _analysisCache.put(
        path: path,
        size: stat.size,
        mtime: stat.modified.millisecondsSinceEpoch,
        bpm: d.bpm,
        key: d.key,
        beatOffset: d.beatOffset,
      );
    } catch (_) {}
  }

  Future<void> setExternalMixer(bool enabled) async {
    if (mixerOffer != null) {
      mixerOffer = null;
      notifyListeners();
    }
    var deviceId = 0;
    var usbChannels = 4;
    usbDeviceName = '';
    usbDeviceId = 0;
    await UsbOutput.stopPlayback();
    if (enabled && Platform.isAndroid) {
      final usb = await UsbOutput.find();
      if (usb != null) {
        deviceId = usb.id;
        usbDeviceName = usb.name;
        if (usb.channels >= 8) usbChannels = 8;
      }
    }
    final prepared = _engine.setExternalMixer(enabled);
    if (enabled && prepared && Platform.isAndroid) {
      final res = await UsbOutput.startPlayback(
        engineHandle: _engine.nativeHandle,
        deviceId: deviceId,
        channels: usbChannels,
      );
      externalMixer = res.ok;
      if (res.ok) {
        usbDeviceId = res.routedId != 0 ? res.routedId : deviceId;
        if (res.routedName.isNotEmpty) usbDeviceName = res.routedName;
        engineError = null;
      } else {
        await UsbOutput.stopPlayback();
        engineError =
            'This USB device cannot take Deck A and Deck B on separate '
            'channels; audio stayed on the phone.';
        _engine.setExternalMixer(false);
        externalMixer = false;
      }
    } else if (enabled && !prepared) {
      engineError = '4-channel USB open failed; audio stayed on phone stereo.';
      externalMixer = false;
    } else {
      externalMixer = false;
      if (!enabled) engineError = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (recordingPath != null) _engine.recordStop();
    _usbSub?.cancel();
    _ticker.cancel();
    _nudgeHold[0]?.cancel();
    _nudgeHold[1]?.cancel();
    UsbOutput.stopPlayback();
    _engine.dispose();
    super.dispose();
  }
}
