import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidedeck/engine/usb_output.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';

/// Compact mixer between the two pad blocks: EQ + filter per deck, channel
/// faders, crossfader and the library / settings buttons.
class MixerStrip extends StatelessWidget {
  const MixerStrip({
    super.key,
    required this.controller,
    required this.onLibrary,
    required this.onSettings,
  });

  final DjController controller;
  final VoidCallback onLibrary;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    if (controller.externalMixer) {
      return _externalCenter();
    }
    final a = controller.deckA;
    final b = controller.deckB;
    return Row(
      children: [
        SizedBox(width: 104, child: _eqBlock(0, a, SideDeckTheme.accentA)),
        _channelFader(0, a, SideDeckTheme.accentA),
        _pflButton(0, SideDeckTheme.accentA),
        Expanded(child: _center()),
        _pflButton(1, SideDeckTheme.accentB),
        _channelFader(1, b, SideDeckTheme.accentB),
        SizedBox(width: 104, child: _eqBlock(1, b, SideDeckTheme.accentB)),
      ],
    );
  }

  Widget _center() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _iconBtn(Icons.library_music_outlined, 'Library', onLibrary),
            const SizedBox(width: 6),
            _iconBtn(Icons.settings_outlined, 'Settings', onSettings),
          ],
        ),
        const Spacer(),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: SideDeckTheme.accentA,
            inactiveTrackColor: SideDeckTheme.accentB,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: CenterDetentSlider(
            value: controller.xfader,
            onChanged: controller.setXfader,
          ),
        ),
        const Text(
          'CROSSFADER',
          style: TextStyle(
            fontSize: 8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: SideDeckTheme.muted,
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _externalCenter() {
    final name = UsbOutput.deviceLabel(controller.usbDeviceName);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _iconBtn(Icons.library_music_outlined, 'Library', onLibrary),
            const SizedBox(width: 10),
            _iconBtn(Icons.settings_outlined, 'Settings', onSettings),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'EXTERNAL MIXER',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: SideDeckTheme.muted,
          ),
        ),
        if (name.isNotEmpty)
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: SideDeckTheme.text),
          ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: SideDeckTheme.panelAlt,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: SideDeckTheme.stroke),
          ),
          child: Icon(icon, size: 18, color: SideDeckTheme.text),
        ),
      ),
    );
  }

  /// Headphone cue; only audible on a 4-channel output (controller card).
  Widget _pflButton(int deck, Color accent) {
    final on = controller.pfl[deck];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => controller.setPfl(deck, !on),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? accent : SideDeckTheme.panelAlt,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: on ? accent : SideDeckTheme.stroke),
          ),
          child: Icon(Icons.headphones, size: 16, color: on ? Colors.black : SideDeckTheme.muted),
        ),
      ),
    );
  }

  Widget _channelFader(int deck, DeckState d, Color accent) {
    return SizedBox(
      width: 26,
      child: Column(
        children: [
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbColor: Colors.white,
                  activeTrackColor: accent,
                  inactiveTrackColor: SideDeckTheme.panelAlt,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: d.fader.clamp(0.0, 1.0),
                  onChanged: (v) => controller.setFader(deck, v),
                ),
              ),
            ),
          ),
          const Text(
            'VOL',
            style: TextStyle(fontSize: 8, color: SideDeckTheme.muted, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _eqBlock(int deck, DeckState d, Color accent) {
    return Row(
      children: [
        Expanded(
          child: _vSlider('LOW', d.eqLow, -12, 12, accent, (v) => controller.setEq(deck, low: v)),
        ),
        Expanded(
          child: _vSlider('MID', d.eqMid, -12, 12, accent, (v) => controller.setEq(deck, mid: v)),
        ),
        Expanded(
          child: _vSlider('HIGH', d.eqHigh, -12, 12, accent, (v) => controller.setEq(deck, high: v)),
        ),
        Expanded(
          child: _vSlider('FILT', d.filter, -1, 1, accent, (v) => controller.setFilter(deck, v)),
        ),
      ],
    );
  }

  Widget _vSlider(
    String label,
    double value,
    double min,
    double max,
    Color accent,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbColor: accent,
                activeTrackColor: accent.withValues(alpha: 0.8),
                inactiveTrackColor: SideDeckTheme.panelAlt,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: CenterDetentSlider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 8, color: SideDeckTheme.muted, letterSpacing: 0.5),
        ),
      ],
    );
  }
}

/// Follows the finger. A center notch only appears after you leave the
/// middle and come back in the same drag.
class CenterDetentSlider extends StatefulWidget {
  const CenterDetentSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<CenterDetentSlider> createState() => _CenterDetentSliderState();
}

class _CenterDetentSliderState extends State<CenterDetentSlider> {
  static const _snapIn = 0.02;
  static const _breakOut = 0.11;

  bool _latched = false;
  bool _leftCenter = false;

  double get _mid => (widget.min + widget.max) / 2;
  double get _range => widget.max - widget.min;

  bool _near(double v, double threshold) => (v - _mid).abs() <= threshold * _range;

  void _onChangeStart(double v) {
    _latched = false;
    _leftCenter = !_near(v, _snapIn);
  }

  void _onChanged(double v) {
    final dist = (v - _mid).abs();

    if (_latched) {
      if (dist >= _breakOut * _range) {
        _latched = false;
        HapticFeedback.lightImpact();
        widget.onChanged(v);
      } else if (widget.value != _mid) {
        widget.onChanged(_mid);
      }
      return;
    }

    if (!_near(v, _snapIn)) {
      _leftCenter = true;
      widget.onChanged(v);
      return;
    }

    if (_leftCenter) {
      _latched = true;
      HapticFeedback.selectionClick();
      widget.onChanged(_mid);
    } else {
      widget.onChanged(v);
    }
  }

  void _onChangeEnd(double v) {
    _latched = false;
    _leftCenter = false;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: widget.value.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      onChangeStart: _onChangeStart,
      onChanged: _onChanged,
      onChangeEnd: _onChangeEnd,
    );
  }
}

/// Tap once, or hold to repeat after a short delay.
class HoldRepeatButton extends StatefulWidget {
  const HoldRepeatButton({
    super.key,
    required this.onStep,
    required this.child,
    this.enabled = true,
    this.delay = const Duration(milliseconds: 380),
    this.interval = const Duration(milliseconds: 70),
  });

  final VoidCallback onStep;
  final Widget child;
  final bool enabled;
  final Duration delay;
  final Duration interval;

  @override
  State<HoldRepeatButton> createState() => _HoldRepeatButtonState();
}

class _HoldRepeatButtonState extends State<HoldRepeatButton> {
  Timer? _delay;
  Timer? _repeat;

  void _start() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onStep();
    _delay = Timer(widget.delay, () {
      _repeat = Timer.periodic(widget.interval, (_) => widget.onStep());
    });
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  @override
  void didUpdateWidget(HoldRepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled ? (_) => _start() : null,
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: widget.child,
    );
  }
}
