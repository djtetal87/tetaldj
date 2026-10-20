import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/waveform.dart';

enum PadMode { hotcue, loop, jump }

/// Serato-style performance block for one deck: a transport column
/// (PLAY, CUE, SYNC, nudge) next to a 4x2 pad grid with mode tabs.
class DeckPads extends StatelessWidget {
  const DeckPads({
    super.key,
    required this.deck,
    required this.dj,
    required this.mode,
    required this.onMode,
  });

  final int deck;
  final DjController dj;
  final PadMode mode;
  final ValueChanged<PadMode> onMode;

  static const padW = 38.0;
  static const padH = 44.0;
  static const gap = 5.0;
  static const transportW = 52.0;
  static const width = transportW + gap + padW * 4 + gap * 3;

  @override
  Widget build(BuildContext context) {
    final d = dj.deck(deck);
    final accent = SideDeckTheme.accent(deck);
    final mirrored = deck == 1;
    final transport = _transport(d, accent);
    final pads = _padBlock(d, accent);
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: mirrored
            ? [pads, const SizedBox(width: gap), transport]
            : [transport, const SizedBox(width: gap), pads],
      ),
    );
  }

  // ---------------------------------------------------------------- transport

  Widget _transport(DeckState d, Color accent) {
    final on = d.loaded;
    final other = dj.deck(1 - deck).loaded;
    return SizedBox(
      width: transportW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _button(
              label: d.playing ? 'PAUSE' : 'PLAY',
              icon: d.playing ? Icons.pause : Icons.play_arrow,
              color: accent,
              filled: d.playing,
              enabled: on,
              onTap: () => dj.playPause(deck),
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            flex: 4,
            child: _button(
              label: 'CUE',
              color: Colors.white,
              filled: on && !d.playing && (d.position - d.cuePoint).abs() < 0.02,
              enabled: on,
              onTap: () => dj.cue(deck),
              onLongPress: () => dj.cuePlay(deck),
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            flex: 4,
            child: _button(
              label: 'SYNC',
              color: accent,
              filled: d.synced,
              enabled: on && other,
              onTap: () => dj.sync(deck),
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(child: _nudge(faster: false, enabled: on)),
                const SizedBox(width: gap),
                Expanded(child: _nudge(faster: true, enabled: on)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nudge({required bool faster, required bool enabled}) {
    return Listener(
      onPointerDown: enabled ? (_) => dj.startNudge(deck, faster: faster) : null,
      onPointerUp: enabled ? (_) => dj.endNudge(deck) : null,
      onPointerCancel: enabled ? (_) => dj.endNudge(deck) : null,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: SideDeckTheme.stroke),
        ),
        child: Icon(
          faster ? Icons.fast_forward : Icons.fast_rewind,
          size: 16,
          color: enabled ? SideDeckTheme.text : SideDeckTheme.muted,
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required Color color,
    required bool filled,
    required bool enabled,
    IconData? icon,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final fg = !enabled
        ? SideDeckTheme.muted
        : filled
            ? Colors.black
            : color;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap?.call();
            }
          : null,
      onLongPress: enabled ? onLongPress : null,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled && enabled ? color : SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.8) : SideDeckTheme.stroke,
            width: 1.2,
          ),
          boxShadow: filled && enabled
              ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)]
              : null,
        ),
        child: icon != null
            ? Icon(icon, size: 24, color: fg)
            : Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: fg,
                ),
              ),
      ),
    );
  }

  // --------------------------------------------------------------------- pads

  Widget _padBlock(DeckState d, Color accent) {
    return SizedBox(
      width: padW * 4 + gap * 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabs(accent),
          const SizedBox(height: gap),
          Expanded(child: _grid(d, accent)),
        ],
      ),
    );
  }

  Widget _tabs(Color accent) {
    Widget tab(PadMode m, String label) {
      final on = mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => onMode(m),
          child: Container(
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? accent.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border(
                bottom: BorderSide(
                  color: on ? accent : SideDeckTheme.stroke,
                  width: on ? 2 : 1,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: on ? accent : SideDeckTheme.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(PadMode.hotcue, 'HOT CUE'),
        const SizedBox(width: 3),
        tab(PadMode.loop, 'LOOP'),
        const SizedBox(width: 3),
        tab(PadMode.jump, 'JUMP'),
      ],
    );
  }

  Widget _grid(DeckState d, Color accent) {
    final cells = switch (mode) {
      PadMode.hotcue => _hotcuePads(d),
      PadMode.loop => _loopPads(d),
      PadMode.jump => _jumpPads(d),
    };
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 4; col++) ...[
                  Expanded(child: cells[row * 4 + col]),
                  if (col < 3) const SizedBox(width: gap),
                ],
              ],
            ),
          ),
          if (row == 0) const SizedBox(height: gap),
        ],
      ],
    );
  }

  List<Widget> _hotcuePads(DeckState d) {
    return [
      for (var slot = 0; slot < 8; slot++)
        _pad(
          color: WaveformPainter.hotcueColors[slot],
          filled: slot < d.hotcues.length && d.hotcues[slot] >= 0,
          enabled: d.loaded,
          label: '${slot + 1}',
          onTap: () => dj.hotcue(deck, slot),
          onLongPress: () => dj.clearHotcue(deck, slot),
        ),
    ];
  }

  static const _loopSizes = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];

  List<Widget> _loopPads(DeckState d) {
    final current = d.loopBars * 4;
    return [
      for (final beats in _loopSizes)
        _pad(
          color: SideDeckTheme.loop,
          filled: d.loopEnabled && (current - beats).abs() < 0.05,
          enabled: d.loaded,
          label: beats < 1 ? '1/${(1 / beats).round()}' : '${beats.round()}',
          onTap: () {
            final same = d.loopEnabled && (current - beats).abs() < 0.05;
            dj.setLoop(deck, !same, beats / 4.0);
          },
        ),
    ];
  }

  List<Widget> _jumpPads(DeckState d) {
    const back = [-16, -8, -4, -1];
    const fwd = [1, 4, 8, 16];
    Widget jump(int beats) => _pad(
          color: SideDeckTheme.accent(deck),
          filled: false,
          enabled: d.loaded,
          label: beats < 0 ? '◀ ${-beats}' : '$beats ▶',
          onTap: () => dj.beatJump(deck, beats),
        );
    return [for (final b in back) jump(b), for (final b in fwd) jump(b)];
  }

  Widget _pad({
    required Color color,
    required bool filled,
    required bool enabled,
    required String label,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final fg = !enabled
        ? SideDeckTheme.muted
        : filled
            ? Colors.black
            : Colors.white;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap?.call();
            }
          : null,
      onLongPress: enabled ? onLongPress : null,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled && enabled ? color : SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? color.withValues(alpha: filled ? 1 : 0.7) : SideDeckTheme.stroke,
            width: 1.2,
          ),
          boxShadow: filled && enabled
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: fg,
          ),
        ),
      ),
    );
  }
}
