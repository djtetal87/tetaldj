import 'package:flutter/material.dart';
import 'package:sidedeck/engine/music_utils.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/mixer_strip.dart';

/// Serato-style deck strip above the waveform: deck badge, title / artist,
/// loop state, BPM with tempo nudges, Camelot key chip and remaining time.
class DeckHeader extends StatelessWidget {
  const DeckHeader({
    super.key,
    required this.deck,
    required this.state,
    required this.dj,
    required this.gridEditing,
    required this.onToggleGrid,
    required this.onLoad,
  });

  final int deck;
  final DeckState state;
  final DjController dj;
  final bool gridEditing;
  final VoidCallback onToggleGrid;
  final VoidCallback onLoad;

  static const height = 30.0;

  @override
  Widget build(BuildContext context) {
    final d = state;
    final accent = SideDeckTheme.accent(deck);
    final remaining = (d.duration - d.position).clamp(0.0, 99999.0);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          _badge(accent),
          const SizedBox(width: 8),
          Expanded(
            child: d.loaded
                ? _title(d)
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onLoad,
                    child: Row(
                      children: [
                        const Icon(Icons.add_circle_outline,
                            size: 16, color: SideDeckTheme.muted),
                        const SizedBox(width: 6),
                        Text(
                          'Cargar un track',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SideDeckTheme.muted.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (d.loaded && d.loopEnabled) ...[
            _chip(
              _loopLabel(d),
              fg: Colors.black,
              bg: SideDeckTheme.loop,
            ),
            const SizedBox(width: 6),
          ],
          if (d.loaded) ...[
            _tempo(accent),
            const SizedBox(width: 8),
            _keyChip(d),
            const SizedBox(width: 8),
            Text(
              '-${formatDuration(remaining)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
                color: SideDeckTheme.text,
              ),
            ),
            const SizedBox(width: 6),
            _gridButton(accent),
          ],
        ],
      ),
    );
  }

  Widget _badge(Color accent) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        deck == 0 ? 'A' : 'B',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _title(DeckState d) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          d.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: SideDeckTheme.text,
          ),
        ),
        if (d.artist.isNotEmpty)
          Text(
            d.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              height: 1.1,
              color: SideDeckTheme.muted,
            ),
          ),
      ],
    );
  }

  String _loopLabel(DeckState d) {
    final beats = d.loopBars * 4;
    final n = (beats - beats.round()).abs() < 0.05
        ? '${beats.round()}'
        : beats.toStringAsFixed(1);
    return 'LOOP $n';
  }

  Widget _tempo(Color accent) {
    final d = state;
    final heard = d.bpm * d.rate;
    final label = d.bpm > 1 ? heard.toStringAsFixed(1) : '--.-';
    final shifted = (d.rate - 1.0).abs() > 0.002;
    Widget step(IconData icon, double delta) {
      return HoldRepeatButton(
        enabled: d.bpm > 1,
        onStep: () => dj.nudgeBpm(deck, delta),
        child: SizedBox(
          width: 22,
          height: 26,
          child: Icon(icon, size: 16, color: SideDeckTheme.muted),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        step(Icons.remove, -0.1),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: d.synced ? accent : SideDeckTheme.text,
              ),
            ),
            Text(
              shifted
                  ? '${d.rate >= 1 ? '+' : ''}${((d.rate - 1) * 100).toStringAsFixed(1)}%'
                  : 'BPM',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                height: 1,
                color: SideDeckTheme.muted,
              ),
            ),
          ],
        ),
        step(Icons.add, 0.1),
      ],
    );
  }

  Widget _keyChip(DeckState d) {
    final wheel = camelotWheel(d.key);
    if (wheel == null) {
      return _chip('--', fg: SideDeckTheme.muted, bg: SideDeckTheme.panelAlt);
    }
    final c = SideDeckTheme.camelot[(wheel.number - 1).clamp(0, 11)];
    return _chip(
      '${wheel.number}${wheel.minor ? 'A' : 'B'}',
      fg: Colors.black,
      bg: c,
    );
  }

  Widget _chip(String text, {required Color fg, required Color bg}) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }

  Widget _gridButton(Color accent) {
    return GestureDetector(
      onTap: onToggleGrid,
      child: Container(
        width: 30,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: gridEditing ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: gridEditing ? accent : SideDeckTheme.stroke,
          ),
        ),
        child: Icon(
          Icons.grid_4x4,
          size: 14,
          color: gridEditing ? Colors.black : SideDeckTheme.muted,
        ),
      ),
    );
  }
}
