import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A controller mapping loaded from assets/midi/*.json: which MIDI message
/// means which action, per deck, per pad bank, or globally.
class MidiMapping {
  MidiMapping._(this.name, this.match, this.jogTicksPerRev, this.tempoInverted,
      this.deckChannels, this.padChannels, this.deckNotes, this.deckCc,
      this.padBanks, this.globalChannel, this.globalNotes, this.globalCc, this.leds);

  final String name;
  final List<String> match;
  final int jogTicksPerRev;
  final bool tempoInverted;
  final List<int> deckChannels;
  final List<int> padChannels;
  final Map<int, String> deckNotes;
  final Map<int, String> deckCc;
  /// Pad bank name -> first note (8 consecutive notes per bank).
  final Map<String, int> padBanks;
  final int globalChannel;
  final Map<int, String> globalNotes;
  final Map<int, String> globalCc;
  final Map<String, int> leds;

  static const assets = ['assets/midi/pioneer-ddj-sr.json'];

  static Future<List<MidiMapping>> loadAll() async {
    final out = <MidiMapping>[];
    for (final a in assets) {
      try {
        out.add(parse(await rootBundle.loadString(a)));
      } catch (_) {}
    }
    return out;
  }

  static int _hex(String s) => int.parse(s.trim().replaceFirst('0x', ''), radix: 16);

  static Map<int, String> _table(Map<String, dynamic>? m) =>
      {for (final e in (m ?? const {}).entries) _hex(e.key): e.value as String};

  static MidiMapping parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final decks = (j['decks'] as List).cast<Map<String, dynamic>>();
    final banks = <String, int>{};
    for (final e in (j['padNotes'] as Map<String, dynamic>? ?? const {}).entries) {
      banks[e.value as String] = _hex(e.key.split('-').first);
    }
    final g = j['global'] as Map<String, dynamic>? ?? const {};
    return MidiMapping._(
      j['name'] as String,
      (j['match'] as List?)?.cast<String>() ?? const [],
      (j['jogTicksPerRev'] as num?)?.toInt() ?? 2048,
      j['tempoInverted'] as bool? ?? false,
      [for (final d in decks) (d['channel'] as num).toInt()],
      [for (final d in decks) (d['padChannel'] as num).toInt()],
      _table(j['deckNotes'] as Map<String, dynamic>?),
      _table(j['deckCc'] as Map<String, dynamic>?),
      banks,
      (g['channel'] as num?)?.toInt() ?? 6,
      _table(g['notes'] as Map<String, dynamic>?),
      _table(g['cc'] as Map<String, dynamic>?),
      {for (final e in (j['leds'] as Map<String, dynamic>? ?? const {}).entries) e.key: _hex(e.value as String)},
    );
  }

  bool matches(String deviceName) {
    final n = deviceName.toUpperCase();
    return match.any((m) => n.contains(m.toUpperCase()));
  }
}

/// One decoded incoming message.
class MidiAction {
  const MidiAction(this.name, {this.deck = -1, this.index = 0, this.value = 0, this.isNote = false});
  final String name;
  final int deck; // -1 = global
  final int index; // pad slot
  final int value; // velocity or CC value
  final bool isNote;

  @override
  String toString() => 'MidiAction($name deck=$deck idx=$index v=$value)';
}

extension MidiMappingDecode on MidiMapping {
  MidiAction? decode(int status, int d1, int d2) {
    final type = status & 0xF0;
    final ch = status & 0x0F;
    if (type != 0x90 && type != 0x80 && type != 0xB0) return null;
    final isNote = type != 0xB0;
    final value = type == 0x80 ? 0 : d2;
    final deck = deckChannels.indexOf(ch);
    if (deck >= 0) {
      final table = isNote ? deckNotes : deckCc;
      final name = table[d1];
      return name == null ? null : MidiAction(name, deck: deck, value: value, isNote: isNote);
    }
    final pad = padChannels.indexOf(ch);
    if (pad >= 0 && isNote) {
      for (final e in padBanks.entries) {
        if (d1 >= e.value && d1 < e.value + 8) {
          return MidiAction(e.key, deck: pad, index: d1 - e.value, value: value, isNote: true);
        }
      }
      return null;
    }
    if (ch == globalChannel) {
      final name = (isNote ? globalNotes : globalCc)[d1];
      return name == null ? null : MidiAction(name, value: value, isNote: isNote);
    }
    return null;
  }
}
