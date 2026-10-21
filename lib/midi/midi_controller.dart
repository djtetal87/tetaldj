import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:sidedeck/midi/midi_mapping.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/state/library_controller.dart';

/// Connects MIDI controllers to the decks: picks the mapping that matches the
/// device name, decodes every message into an action, drives the
/// [DjController], and lights the controller's LEDs from deck state.
class MidiController extends ChangeNotifier {
  MidiController(this.dj, this.library) {
    _mappings = MidiMapping.loadAll();
    _midi = MidiCommand();
    _sub = _midi.onMidiDataReceived?.listen(_onPacket);
    _setupSub = _midi.onMidiSetupChanged?.listen((_) => refresh());
    dj.addListener(_onDeckChanged);
    refresh();
  }

  final DjController dj;
  final LibraryController library;
  late final MidiCommand _midi;
  late final Future<List<MidiMapping>> _mappings;
  StreamSubscription<MidiDataReceivedEvent>? _sub;
  StreamSubscription<MidiSetupChange>? _setupSub;

  List<MidiDevice> devices = const [];
  MidiDevice? connected;
  MidiMapping? mapping;
  String status = 'Sin controladora';
  /// Last decoded action, for the settings page "MIDI monitor".
  String lastMessage = '';

  // Per-deck state the controller needs that the engine doesn't.
  final List<bool> _shift = [false, false];
  final List<bool> _vinyl = [true, true];

  bool get vinylMode => _vinyl[0];
  void setVinylMode(bool on) {
    _vinyl[0] = on;
    _vinyl[1] = on;
    _led(0, 'vinyl', on);
    _led(1, 'vinyl', on);
    notifyListeners();
  }
  final List<bool> _touching = [false, false];
  final List<int> _lastTickUs = [0, 0];
  final List<Timer?> _still = [null, null];
  final Map<String, int> _msb = {};
  int _browseIndex = 0;

  // ------------------------------------------------------------ connection

  Future<void> refresh() async {
    try {
      devices = (await _midi.devices) ?? const [];
    } catch (_) {
      devices = const [];
    }
    final maps = await _mappings;
    // Auto-connect to the first device a mapping knows.
    if (connected == null) {
      for (final d in devices) {
        final m = maps.where((m) => m.matches(d.name)).firstOrNull;
        if (m != null) {
          await connect(d, m);
          break;
        }
      }
    } else if (!devices.any((d) => d.id == connected!.id)) {
      connected = null;
      mapping = null;
      status = 'Controladora desconectada';
    }
    notifyListeners();
  }

  Future<void> connect(MidiDevice device, [MidiMapping? map]) async {
    final maps = await _mappings;
    final m = map ?? maps.where((m) => m.matches(device.name)).firstOrNull ?? maps.firstOrNull;
    try {
      await _midi.connectToDevice(device);
      connected = device;
      mapping = m;
      status = '${device.name} · ${m?.name ?? 'sin mapeo'}';
      _initLeds();
    } catch (e) {
      status = 'No se pudo conectar: $e';
    }
    notifyListeners();
  }

  void disconnect() {
    final d = connected;
    if (d != null) _midi.disconnectDevice(d);
    connected = null;
    mapping = null;
    status = 'Sin controladora';
    notifyListeners();
  }

  // --------------------------------------------------------------- input

  void _onPacket(MidiDataReceivedEvent p) {
    final m = mapping;
    if (m == null) return;
    final data = p.message.data;
    var i = 0;
    while (i + 2 < data.length + 1 && i < data.length) {
      final status = data[i];
      if (status < 0x80) {
        i++;
        continue;
      }
      final type = status & 0xF0;
      final len = (type == 0xC0 || type == 0xD0) ? 2 : 3;
      if (i + len > data.length) break;
      final d1 = data[i + 1];
      final d2 = len == 3 ? data[i + 2] : 0;
      final action = m.decode(status, d1, d2);
      if (action != null) {
        lastMessage = action.toString();
        _handle(action, m, p.timestamp);
      }
      i += len;
    }
  }

  int _value14(String key, String suffix, int value, {required bool msb}) {
    // Pioneer sends MSB then LSB on cc and cc+0x20; combine when the LSB arrives.
    if (msb) {
      _msb[key] = value;
      return -1;
    }
    return ((_msb[key] ?? 0) << 7) | value;
  }

  void _handle(MidiAction a, MidiMapping m, int timestamp) {
    final deck = a.deck;
    final on = a.value > 0;
    final name = a.name;

    // Global
    if (deck < 0) {
      if (name.endsWith('MSB') || name.endsWith('LSB')) {
        final base = name.substring(0, name.length - 3);
        final v = _value14('g.$base', '', a.value, msb: name.endsWith('MSB'));
        if (v < 0) return;
        final f = v / 16383.0;
        switch (base) {
          case 'xfader':
            dj.setXfader(f);
          case 'filter0':
            dj.setFilter(0, (f - 0.5) * 2);
          case 'filter1':
            dj.setFilter(1, (f - 0.5) * 2);
          case 'master':
            dj.setMaster(f);
          case 'cueMix':
            dj.setCueMix(f);
          case 'cueGain':
            dj.setCueGain(f * 1.5);
        }
        return;
      }
      switch (name) {
        case 'load0':
          if (on) _loadSelected(0);
        case 'load1':
          if (on) _loadSelected(1);
        case 'browse':
        case 'browseShift':
          _browse(a.value >= 0x40 ? a.value - 0x80 : a.value);
        case 'browseClick':
          if (on) _loadSelected(_browseIndex % 2);
      }
      return;
    }

    // Pads
    switch (name) {
      case 'hotcue':
        if (on) dj.hotcue(deck, a.index);
        return;
      case 'clearHotcue':
        if (on) dj.clearHotcue(deck, a.index);
        return;
      case 'roll':
        if (on) {
          const sizes = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];
          final d = dj.deck(deck);
          final beats = sizes[a.index];
          final same = d.loopEnabled && (d.loopBars * 4 - beats).abs() < 0.05;
          dj.setLoop(deck, !same, beats / 4.0);
        }
        return;
      case 'slicer':
        if (on) {
          const jumps = [-16, -8, -4, -1, 1, 4, 8, 16];
          dj.beatJump(deck, jumps[a.index]);
        }
        return;
      case 'sampler':
        if (on && a.index < 4) {
          // Sampler pads double as stem toggles while there is no sampler.
          if (dj.deck(deck).stemsOn) dj.toggleStem(deck, a.index);
        }
        return;
    }

    // Deck CC (faders / knobs / jog)
    if (!a.isNote) {
      switch (name) {
        case 'jogTick':
          _jog(deck, a.value - 0x40, m, timestamp, ring: false);
          return;
        case 'jogTickShift':
          _jog(deck, (a.value - 0x40) * 10, m, timestamp, ring: false);
          return;
        case 'jogRing':
          _jog(deck, a.value - 0x40, m, timestamp, ring: true);
          return;
        case 'jogRingShift':
          _jog(deck, (a.value - 0x40) * 10, m, timestamp, ring: true);
          return;
      }
      if (name.endsWith('MSB') || name.endsWith('LSB')) {
        final base = name.substring(0, name.length - 3);
        final v = _value14('$deck.$base', '', a.value, msb: name.endsWith('MSB'));
        if (v < 0) return;
        final f = v / 16383.0;
        switch (base) {
          case 'tempo':
            // Fader up = slower on Pioneer (0 at the top = +range).
            final t = m.tempoInverted ? f : 1 - f;
            dj.setRate(deck, 1 + (t - 0.5) * 2 * 0.16);
          case 'fader':
            dj.setFader(deck, f);
          case 'gain':
            dj.setGain(deck, f < 0.5 ? f * 2 : 1 + (f - 0.5) * 1.0);
          case 'eqLow':
            dj.setEq(deck, low: _eqDb(f));
          case 'eqMid':
            dj.setEq(deck, mid: _eqDb(f));
          case 'eqHigh':
            dj.setEq(deck, high: _eqDb(f));
          case 'needle':
            final d = dj.deck(deck);
            if (d.loaded) dj.seekTo(deck, f * d.duration);
        }
      }
      return;
    }

    // Deck buttons
    switch (name) {
      case 'shift':
        _shift[deck] = on;
      case 'play':
        if (on) dj.playPause(deck);
      case 'cue':
        if (_shift[deck]) {
          if (on) dj.seekTo(deck, 0);
        } else if (on) {
          dj.cue(deck);
        } else {
          // Releasing CUE while held = cue play, like Serato: handled by the
          // engine's cue semantics (press = cue; hold/release stays on cue).
        }
      case 'sync':
        if (on) dj.sync(deck);
      case 'pfl':
        if (on) dj.setPfl(deck, !dj.pfl[deck]);
      case 'keylock':
        if (on) dj.setKeylock(deck, !dj.deck(deck).keylock);
      case 'autoloop':
        if (on) {
          final d = dj.deck(deck);
          dj.setLoop(deck, !d.loopEnabled, d.loopBars);
        }
      case 'loopHalf':
        if (on) dj.halfLoop(deck);
      case 'loopDouble':
        if (on) dj.doubleLoop(deck);
      case 'vinyl':
        if (on) {
          _vinyl[deck] = !_vinyl[deck];
          _led(deck, 'vinyl', _vinyl[deck]);
        }
      case 'jogTouch':
        if (_vinyl[deck]) {
          if (on && !_touching[deck]) {
            _touching[deck] = true;
            dj.platterTouch(deck);
          } else if (!on && _touching[deck]) {
            _touching[deck] = false;
            _still[deck]?.cancel();
            dj.platterRelease(deck);
          }
        }
      case 'tempoReset':
        if (on) dj.setRate(deck, 1);
      case 'padModeHotcue':
      case 'padModeRoll':
      case 'padModeSlicer':
      case 'padModeSampler':
        if (on) _padModeLeds(deck, name);
    }
  }

  static double _eqDb(double f) {
    // Centre detent = 0 dB; full left = -26 dB (kill-ish), full right = +6 dB.
    if (f < 0.5) return -26 + (f / 0.5) * 26;
    return ((f - 0.5) / 0.5) * 6;
  }

  void _jog(int deck, int delta, MidiMapping m, int timestamp, {required bool ring}) {
    if (delta == 0) return;
    if (!ring && _vinyl[deck] && _touching[deck]) {
      // Scratch: ticks per revolution -> seconds of audio at 33 rpm.
      final nowUs = timestamp > 0 ? timestamp : DateTime.now().microsecondsSinceEpoch;
      final last = _lastTickUs[deck];
      _lastTickUs[deck] = nowUs;
      final dt = last == 0 ? 0.016 : ((nowUs - last) / 1e6).clamp(0.002, 0.25);
      final seconds = delta / m.jogTicksPerRev * 1.8;
      dj.platterScratch(deck, seconds / dt);
      _still[deck]?.cancel();
      _still[deck] = Timer(const Duration(milliseconds: 45), () {
        if (_touching[deck]) dj.platterScratch(deck, 0);
      });
      return;
    }
    // Ring / non-vinyl: pitch bend proportional to how fast the wheel moves.
    dj.jogBend(deck, (delta / 5.0).clamp(-1.0, 1.0));
  }

  void _browse(int delta) {
    final n = library.filtered.length;
    if (n == 0) return;
    _browseIndex = (_browseIndex + delta).clamp(0, n - 1);
    library.highlight(_browseIndex);
  }

  void _loadSelected(int deck) {
    final list = library.filtered;
    if (list.isEmpty) return;
    final t = list[_browseIndex.clamp(0, list.length - 1)];
    dj.loadFile(deck, t.path, title: t.title, artist: t.artist);
  }

  // ---------------------------------------------------------------- LEDs

  void _send(int status, int d1, int d2) {
    if (connected == null) return;
    try {
      _midi.sendData(Uint8List.fromList([status, d1, d2]));
    } catch (_) {}
  }

  void _led(int deck, String key, bool on) {
    final m = mapping;
    if (m == null) return;
    final note = m.leds[key];
    if (note == null || deck >= m.deckChannels.length) return;
    _send(0x90 | m.deckChannels[deck], note, on ? 0x7F : 0x00);
  }

  void _padLed(int deck, String bank, int index, bool on) {
    final m = mapping;
    if (m == null) return;
    final base = m.padBanks[bank];
    if (base == null || deck >= m.padChannels.length) return;
    _send(0x90 | m.padChannels[deck], base + index, on ? 0x7F : 0x00);
  }

  void _padModeLeds(int deck, String active) {
    for (final k in const ['padModeHotcue', 'padModeRoll', 'padModeSlicer', 'padModeSampler']) {
      _led(deck, k, k == active);
    }
  }

  final List<String> _ledState = ['', ''];

  void _initLeds() {
    for (var deck = 0; deck < 2; deck++) {
      _led(deck, 'vinyl', _vinyl[deck]);
      _padModeLeds(deck, 'padModeHotcue');
      _ledState[deck] = '';
    }
    _onDeckChanged();
  }

  void _onDeckChanged() {
    if (connected == null || mapping == null) return;
    for (var deck = 0; deck < 2; deck++) {
      final d = dj.deck(deck);
      final sig = '${d.playing}${d.synced}${d.keylock}${d.loopEnabled}${dj.pfl[deck]}'
          '${d.hotcues.map((h) => h >= 0 ? 1 : 0).join()}${d.loaded}';
      if (sig == _ledState[deck]) continue;
      _ledState[deck] = sig;
      _led(deck, 'play', d.playing);
      _led(deck, 'cue', d.loaded && !d.playing);
      _led(deck, 'sync', d.synced);
      _led(deck, 'keylock', d.keylock);
      _led(deck, 'autoloop', d.loopEnabled);
      _led(deck, 'pfl', dj.pfl[deck]);
      for (var i = 0; i < 8 && i < d.hotcues.length; i++) {
        _padLed(deck, 'hotcue', i, d.hotcues[i] >= 0);
      }
    }
  }

  @override
  void dispose() {
    dj.removeListener(_onDeckChanged);
    _sub?.cancel();
    _setupSub?.cancel();
    for (final t in _still) {
      t?.cancel();
    }
    super.dispose();
  }
}
