import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidedeck/engine/music_utils.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/mixer_strip.dart';

/// Touch jog wheel. Spins with the track; drag it to nudge while playing or
/// to scrub while paused. Shows BPM, pitch, elapsed and remaining time.
class Platter extends StatefulWidget {
  const Platter({
    super.key,
    required this.deck,
    required this.dj,
    required this.size,
  });

  final int deck;
  final DjController dj;
  final double size;

  @override
  State<Platter> createState() => _PlatterState();
}

class _PlatterState extends State<Platter> {
  double? _lastAngle;

  DeckState get d => widget.dj.deck(widget.deck);

  double _angleOf(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    return math.atan2(local.dy - c.dy, local.dx - c.dx);
  }

  // Vinyl mode: a finger on the platter holds the record; dragging moves
  // it (one turn = 1.8 s, like 33 rpm); lifting lets it play again.
  void _onDown(PointerDownEvent e) {
    if (!d.loaded) return;
    _lastAngle = _angleOf(e.localPosition);
    HapticFeedback.selectionClick();
    widget.dj.platterTouch(widget.deck);
  }

  void _onUpdate(PointerMoveEvent e) {
    if (!d.loaded || _lastAngle == null) return;
    final a = _angleOf(e.localPosition);
    var delta = a - _lastAngle!;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastAngle = a;
    if (delta.abs() < 1e-4) return;
    final seconds = delta / (2 * math.pi) * 1.8;
    widget.dj.seekTo(
      widget.deck,
      (d.position + seconds).clamp(0.0, d.duration),
    );
  }

  void _onEnd([dynamic _]) {
    _lastAngle = null;
    widget.dj.platterRelease(widget.deck);
  }

  @override
  Widget build(BuildContext context) {
    final accent = SideDeckTheme.accent(widget.deck);
    final s = widget.size;
    final remaining = (d.duration - d.position).clamp(0.0, 99999.0);
    // 33 rpm: one revolution every 1.8 s of track time.
    final angle = d.loaded ? (d.position / 1.8) * 2 * math.pi : 0.0;
    final heard = d.bpm * d.rate;
    final pitch = (d.rate - 1) * 100;

    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onUpdate,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (d.playing)
              Container(
                width: s * 1.15,
                height: s * 1.15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [accent.withValues(alpha: 0.35), Colors.transparent],
                  ),
                ),
              ),
            CustomPaint(
              size: Size(s, s),
              painter: _PlatterPainter(
                loaded: d.loaded,
                angle: angle,
                accent: accent,
              ),
            ),
            if (d.loaded)
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.bpm > 1 ? heard.toStringAsFixed(1) : '--.-',
                      style: TextStyle(
                        fontSize: s * 0.11,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: d.synced ? accent : Colors.black,
                      ),
                    ),
                    Text(
                      'BPM',
                      style: TextStyle(
                        fontSize: s * 0.055,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: s * 0.03),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${pitch >= 0 ? '+' : ''}${pitch.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: s * 0.07,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(width: s * 0.18),
                        Text(
                          formatKeyShort(d.key),
                          style: TextStyle(
                            fontSize: s * 0.07,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: s * 0.04),
                    Text(
                      formatDuration(d.position),
                      style: TextStyle(
                        fontSize: s * 0.13,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      '-${formatDuration(remaining)}',
                      style: TextStyle(
                        fontSize: s * 0.13,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Camelot-only key label for the platter ("8A", "--").
String formatKeyShort(int key) {
  final w = camelotWheel(key);
  if (w == null) return '--';
  return '${w.number}${w.minor ? 'A' : 'B'}';
}

class _PlatterPainter extends CustomPainter {
  _PlatterPainter({
    required this.loaded,
    required this.angle,
    required this.accent,
  });

  final bool loaded;
  final double angle;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    if (!loaded) {
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFF17181C));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = SideDeckTheme.stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(c, r * 0.12, Paint()..color = const Color(0xFF2A2C33));
      return;
    }
    // Rim in the deck colour, white label like a vinyl centre.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF26272C));
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..color = accent.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(c, r * 0.9, Paint()..color = const Color(0xFFF4F5F7));
    // Position marker rotating with the track.
    final tip = c + Offset(math.cos(angle - math.pi / 2), math.sin(angle - math.pi / 2)) * (r * 0.9);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = Colors.black
        ..strokeWidth = r * 0.12
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, r * 0.08, Paint()..color = const Color(0xFFBDBFC7));
  }

  @override
  bool shouldRepaint(covariant _PlatterPainter old) =>
      old.loaded != loaded || old.angle != angle || old.accent != accent;
}

/// Vertical fader beside the platter that drives either the channel volume
/// or the tempo (±8 %), with a toggle on top and fine ± buttons below.
class PitchStrip extends StatelessWidget {
  const PitchStrip({
    super.key,
    required this.deck,
    required this.dj,
    required this.tempoMode,
    required this.onToggle,
  });

  final int deck;
  final DjController dj;
  final bool tempoMode;
  final VoidCallback onToggle;

  static const range = 0.16;

  @override
  Widget build(BuildContext context) {
    final d = dj.deck(deck);
    final accent = SideDeckTheme.accent(deck);
    final value = tempoMode
        ? ((d.rate - 1) / range).clamp(-1.0, 1.0)
        : d.fader.clamp(0.0, 1.0);
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 58,
              height: 30,
              decoration: BoxDecoration(
                color: SideDeckTheme.panelAlt,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _label('VOL', !tempoMode, accent),
                  _label('BPM', tempoMode, accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => dj.setKeylock(deck, !d.keylock),
            child: Container(
              width: 58,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: d.keylock ? accent.withValues(alpha: 0.2) : SideDeckTheme.panelAlt,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: d.keylock ? accent : SideDeckTheme.stroke,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    d.keylock ? Icons.lock : Icons.lock_open,
                    size: 10,
                    color: d.keylock ? accent : SideDeckTheme.muted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'KEY',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: d.keylock ? accent : SideDeckTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 22,
                  activeTrackColor: accent.withValues(alpha: tempoMode ? 0.25 : 0.8),
                  inactiveTrackColor: SideDeckTheme.panelAlt,
                  thumbColor: Colors.white,
                  thumbShape: const _FaderThumb(),
                  overlayShape: SliderComponentShape.noOverlay,
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: tempoMode
                    ? CenterDetentSlider(
                        value: value,
                        min: -1,
                        max: 1,
                        onChanged: (v) => dj.setRate(deck, 1 + v * range),
                      )
                    : Slider(
                        value: value,
                        onChanged: (v) => dj.setFader(deck, v),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _step(Icons.remove, () {
                if (tempoMode) {
                  dj.nudgeBpm(deck, -0.1);
                } else {
                  dj.setFader(deck, (d.fader - 0.05).clamp(0.0, 1.0));
                }
              }),
              const SizedBox(width: 3),
              _step(Icons.add, () {
                if (tempoMode) {
                  dj.nudgeBpm(deck, 0.1);
                } else {
                  dj.setFader(deck, (d.fader + 0.05).clamp(0.0, 1.0));
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String t, bool on, Color accent) {
    return Text(
      t,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        height: 1.1,
        color: on ? accent : SideDeckTheme.muted,
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback onStep) {
    return HoldRepeatButton(
      onStep: onStep,
      child: Container(
        width: 28,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 16, color: SideDeckTheme.text),
      ),
    );
  }
}

class _FaderThumb extends SliderComponentShape {
  const _FaderThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(18, 30);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 18, height: 30),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFFD8DAE0));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(center.dx - 6, center.dy),
      Offset(center.dx + 6, center.dy),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 2,
    );
  }
}
