import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidedeck/engine/music_utils.dart';
import 'package:sidedeck/engine/usb_output.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/state/library_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/platter.dart';
import 'package:sidedeck/ui/library_drawer.dart';
import 'package:sidedeck/ui/mixer_strip.dart';
import 'package:sidedeck/ui/settings_page.dart';
import 'package:sidedeck/ui/waveform.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.dj, this.library});

  /// Injected controllers (tests / previews); normally created here.
  final DjController? dj;
  final LibraryController? library;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DjController _dj;
  late final LibraryController _library;
  int? _gridEditDeck;
  final _padMode = [PadMode.hotcue, PadMode.hotcue];
  final _padPage = [0, 0];
  final _tempoMode = [false, false];
  bool _mixerDialogOpen = false;
  BuildContext? _mixerDialogContext;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _dj = widget.dj ?? DjController();
    _library = widget.library ?? LibraryController();
    _dj.addListener(_onDjChanged);
  }

  @override
  void dispose() {
    _dj.removeListener(_onDjChanged);
    _dj.dispose();
    _library.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onDjChanged() {
    if (!mounted) return;
    final offer = _dj.mixerOffer;
    if (offer == null) {
      if (_mixerDialogOpen) _dismissMixerDialog();
      return;
    }
    if (_mixerDialogOpen) return;
    _mixerDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = _dj.mixerOffer;
      if (!mounted || next == null) {
        _mixerDialogOpen = false;
        return;
      }
      _showMixerOffer(next);
    });
  }

  void _dismissMixerDialog() {
    final ctx = _mixerDialogContext;
    if (ctx == null) return;
    _mixerDialogContext = null;
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  Future<void> _showMixerOffer(UsbMixerOffer offer) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        _mixerDialogContext = ctx;
        return AlertDialog(
          backgroundColor: SideDeckTheme.panel,
          title: Text('${offer.label} detected'),
          content: const Text(
            'Enable external mixer mode? Deck A and Deck B go out as '
            'separate channels so you mix on hardware.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );
    _mixerDialogContext = null;
    _mixerDialogOpen = false;
    if (!mounted) return;
    if (accepted == true) {
      await _dj.acceptMixerOffer();
    } else if (_dj.mixerOffer != null) {
      _dj.declineMixerOffer();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SettingsPage(dj: _dj)));
  }

  Future<void> _openLibrary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            removeRight: true,
            child: LibraryOverlay(
              dj: _dj,
              library: _library,
              onOpenSettings: () async {
                Navigator.pop(context);
                await _openSettings();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_dj, _library]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: SideDeckTheme.bg,
          body: SafeArea(
            child: Column(
              children: [
                if (_dj.engineError != null) _errorBar(),
                _topBar(),
                Expanded(child: _stage()),
                _bottomPanel(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- top bar

  Widget _topBar() {
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Row(
          children: [
            Expanded(child: _deckInfo(0)),
            const SizedBox(width: 10),
            _wordmark(),
            const SizedBox(width: 10),
            Expanded(child: _deckInfo(1)),
          ],
        ),
      ),
    );
  }

  Widget _wordmark() {
    final rec = _dj.recordingPath != null;
    final secs = _dj.recordingSeconds;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [SideDeckTheme.accentA, SideDeckTheme.accentB],
          ).createShader(r),
          child: const Text(
            'TetalDJ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: rec ? SideDeckTheme.danger : SideDeckTheme.panelAlt,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: rec ? SideDeckTheme.danger : SideDeckTheme.stroke,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rec ? Colors.white : SideDeckTheme.danger,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      rec ? formatDuration(secs) : 'REC',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: rec ? Colors.white : SideDeckTheme.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: SideDeckTheme.panelAlt,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: _openSettings,
                borderRadius: BorderRadius.circular(11),
                child: const SizedBox(
                  width: 28,
                  height: 22,
                  child: Icon(Icons.settings, size: 14, color: SideDeckTheme.muted),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleRecording() async {
    HapticFeedback.mediumImpact();
    if (_dj.recordingPath == null) {
      await _dj.startRecording();
      return;
    }
    final path = _dj.stopRecording();
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SideDeckTheme.panelAlt,
        content: Text(
          'Mix guardado en Grabaciones/${path.split('/').last}',
          style: const TextStyle(color: SideDeckTheme.text),
        ),
      ),
    );
  }

  Widget _deckInfo(int i) {
    final d = _dj.deck(i);
    final accent = SideDeckTheme.accent(i);
    final mirrored = i == 1;
    final load = Material(
      color: SideDeckTheme.panelAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _openLibrary,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(Icons.add, size: 26, color: accent),
        ),
      ),
    );
    final remaining = (d.duration - d.position).clamp(0.0, 99999.0);
    final info = d.loaded
        ? Column(
            crossAxisAlignment:
                mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                textDirection: mirrored ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Expanded(
                    child: Text(
                      d.artist.isNotEmpty ? '${d.title} - ${d.artist}' : d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: mirrored ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SideDeckTheme.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-${formatDuration(remaining)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: SideDeckTheme.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _keyChip(d.key),
                ],
              ),
              const SizedBox(height: 3),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: WaveformView(
                    min: d.waveMin,
                    max: d.waveMax,
                    low: d.waveLow,
                    mid: d.waveMid,
                    high: d.waveHigh,
                    position: d.position,
                    duration: d.duration,
                    color: accent,
                    loopEnabled: d.loopEnabled,
                    loopStart: d.loopStart,
                    loopEnd: d.loopEnd,
                    cuePoint: d.cuePoint,
                    hotcues: d.hotcues,
                    overviewOnly: true,
                    onOverviewSeek: (t) => _dj.seekTo(i, t),
                  ),
                ),
              ),
            ],
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openLibrary,
            child: Align(
              alignment: mirrored ? Alignment.centerRight : Alignment.centerLeft,
              child: const Text(
                'Toca para cargar un tema',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: SideDeckTheme.text,
                ),
              ),
            ),
          );
    return Row(
      children: mirrored
          ? [Expanded(child: info), const SizedBox(width: 8), load]
          : [load, const SizedBox(width: 8), Expanded(child: info)],
    );
  }

  Widget _keyChip(int key) {
    final wheel = camelotWheel(key);
    final bg = wheel == null
        ? SideDeckTheme.panelAlt
        : SideDeckTheme.camelot[(wheel.number - 1).clamp(0, 11)];
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        wheel == null ? '--' : '${wheel.number}${wheel.minor ? 'A' : 'B'}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: wheel == null ? SideDeckTheme.muted : Colors.black,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ stage

  Widget _stage() {
    return LayoutBuilder(
      builder: (context, c) {
        final platter = (c.maxHeight - 12).clamp(120.0, 230.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              PitchStrip(
                deck: 0,
                dj: _dj,
                tempoMode: _tempoMode[0],
                onToggle: () => setState(() => _tempoMode[0] = !_tempoMode[0]),
              ),
              const SizedBox(width: 6),
              Platter(deck: 0, dj: _dj, size: platter),
              const SizedBox(width: 6),
              Expanded(child: _stackedWaves()),
              const SizedBox(width: 6),
              Platter(deck: 1, dj: _dj, size: platter),
              const SizedBox(width: 6),
              PitchStrip(
                deck: 1,
                dj: _dj,
                tempoMode: _tempoMode[1],
                onToggle: () => setState(() => _tempoMode[1] = !_tempoMode[1]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stackedWaves() {
    Widget wave(int i) {
      final d = _dj.deck(i);
      final accent = SideDeckTheme.accent(i);
      return Stack(
        fit: StackFit.expand,
        children: [
          WaveformView(
            min: d.waveMin,
            max: d.waveMax,
            low: d.waveLow,
            mid: d.waveMid,
            high: d.waveHigh,
            position: d.position,
            duration: d.duration,
            beatOffset: d.beatOffset,
            bpm: d.bpm,
            rate: d.rate,
            color: accent,
            loopEnabled: d.loopEnabled,
            loopStart: d.loopStart,
            loopEnd: d.loopEnd,
            cuePoint: d.cuePoint,
            hotcues: d.hotcues,
            zoom: 5,
            showOverview: false,
            onSeek: d.loaded ? (t) => _dj.seek(i, t) : null,
          ),
          if (!d.loaded)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openLibrary,
              ),
            ),
          if (d.loaded && _gridEditDeck == i)
            Positioned(left: 4, bottom: 3, child: _gridEditorBar(i, accent)),
          if (d.loaded)
            Positioned(
              right: 4,
              top: 3,
              child: _gridButton(i, accent),
            ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Expanded(child: wave(0)),
              Container(height: 1, color: SideDeckTheme.stroke),
              Expanded(child: wave(1)),
            ],
          ),
          // One playhead across both decks.
          IgnorePointer(
            child: Center(
              child: Container(width: 2, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridButton(int deck, Color accent) {
    final on = _gridEditDeck == deck;
    return GestureDetector(
      onTap: () => setState(() => _gridEditDeck = on ? null : deck),
      child: Container(
        width: 26,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? accent : const Color(0xAA101114),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.grid_4x4,
          size: 13,
          color: on ? Colors.black : SideDeckTheme.muted,
        ),
      ),
    );
  }

  // ----------------------------------------------------------- bottom panel

  Widget _bottomPanel() {
    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: const BoxDecoration(
        color: SideDeckTheme.panel,
        border: Border(top: BorderSide(color: SideDeckTheme.stroke)),
      ),
      child: Column(
        children: [
          Expanded(child: _transportRow()),
          const SizedBox(height: 8),
          Expanded(child: _padRow()),
        ],
      ),
    );
  }

  Widget _transportRow() {
    Widget side(int i) {
      final d = _dj.deck(i);
      final accent = SideDeckTheme.accent(i);
      final mirrored = i == 1;
      final items = [
        _round(
          icon: Icons.tune,
          color: SideDeckTheme.muted,
          enabled: true,
          onTap: _openMixer,
          wide: true,
        ),
        _round(
          icon: d.playing ? Icons.pause : Icons.play_arrow,
          color: accent,
          filled: d.playing,
          enabled: d.loaded,
          onTap: () => _dj.playPause(i),
        ),
        _round(
          label: 'CUE',
          color: Colors.white,
          enabled: d.loaded,
          onTap: () => _dj.cue(i),
          onLongPress: () => _dj.cuePlay(i),
        ),
        _round(
          label: 'SYNC',
          color: accent,
          filled: d.synced,
          enabled: d.loaded && _dj.deck(1 - i).loaded,
          onTap: () => _dj.sync(i),
        ),
        _loopButton(i),
      ];
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final w in mirrored ? items.reversed : items) ...[
            w,
            const SizedBox(width: 6),
          ],
        ],
      );
    }

    return Row(
      children: [
        side(0),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 34,
              activeTrackColor: SideDeckTheme.panelAlt,
              inactiveTrackColor: SideDeckTheme.panelAlt,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: const _XfaderThumb(),
            ),
            child: CenterDetentSlider(
              value: _dj.xfader,
              onChanged: _dj.setXfader,
            ),
          ),
        ),
        side(1),
      ],
    );
  }

  Widget _loopButton(int i) {
    final d = _dj.deck(i);
    final beats = d.loopBars * 4;
    final label = beats < 1 ? '1/${(1 / beats).round()}' : '${beats.round()}';
    return _round(
      label: label,
      icon: Icons.repeat,
      color: SideDeckTheme.loop,
      filled: d.loopEnabled,
      enabled: d.loaded,
      onTap: () => _dj.setLoop(i, !d.loopEnabled, d.loopBars),
      onLongPress: () => _dj.doubleLoop(i),
    );
  }

  Widget _round({
    String? label,
    IconData? icon,
    required Color color,
    required bool enabled,
    bool filled = false,
    bool wide = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final fg = !enabled
        ? SideDeckTheme.muted.withValues(alpha: 0.6)
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
        width: wide ? 64 : 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled && enabled ? color : SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: enabled && !wide ? color.withValues(alpha: 0.75) : SideDeckTheme.stroke,
            width: 1.5,
          ),
          boxShadow: filled && enabled
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]
              : null,
        ),
        child: icon != null && label != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: fg),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: fg,
                    ),
                  ),
                ],
              )
            : icon != null
                ? Icon(icon, size: 28, color: fg)
                : Text(
                    label!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: fg,
                    ),
                  ),
      ),
    );
  }

  // ------------------------------------------------------------------- pads

  Widget _padRow() {
    return Row(
      children: [
        Expanded(child: _padGroup(0)),
        const SizedBox(width: 12),
        Expanded(child: _padGroup(1)),
      ],
    );
  }

  Widget _padGroup(int i) {
    final mirrored = i == 1;
    final modeBtn = _padModeButton(i);
    final dots = _pageDots(i);
    final pads = Expanded(
      child: Row(
        children: [
          for (var k = 0; k < 4; k++) ...[
            Expanded(child: _padCell(i, _padPage[i] * 4 + k)),
            if (k < 3) const SizedBox(width: 6),
          ],
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: mirrored
            ? [dots, const SizedBox(width: 4), pads, const SizedBox(width: 6), modeBtn]
            : [modeBtn, const SizedBox(width: 6), pads, const SizedBox(width: 4), dots],
      ),
    );
  }

  static const _modeNames = {
    PadMode.hotcue: 'HOT\nCUES',
    PadMode.loop: 'AUTO\nLOOP',
    PadMode.jump: 'BEAT\nJUMP',
  };

  Widget _padModeButton(int i) {
    final m = _padMode[i];
    return GestureDetector(
      onTap: () => setState(() {
        final all = PadMode.values;
        _padMode[i] = all[(all.indexOf(m) + 1) % all.length];
        _padPage[i] = 0;
      }),
      child: Container(
        width: 64,
        decoration: BoxDecoration(
          color: SideDeckTheme.panelAlt,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'PADS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: SideDeckTheme.muted,
              ),
            ),
            Text(
              _modeNames[m]!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: SideDeckTheme.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageDots(int i) {
    final accent = SideDeckTheme.accent(i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _padPage[i] = 1 - _padPage[i]),
      child: SizedBox(
        width: 18,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var p = 0; p < 2; p++) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _padPage[i] == p ? accent : SideDeckTheme.stroke,
                ),
              ),
              if (p == 0) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  static const _loopSizes = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];
  static const _jumpSizes = [-4, -1, 1, 4, -16, -8, 8, 16];

  Widget _padCell(int i, int slot) {
    final d = _dj.deck(i);
    switch (_padMode[i]) {
      case PadMode.hotcue:
        final set = slot < d.hotcues.length && d.hotcues[slot] >= 0;
        return _pad(
          color: WaveformPainter.hotcueColors[slot],
          filled: set,
          enabled: d.loaded,
          label: set ? '${slot + 1}' : '',
          onTap: () => _dj.hotcue(i, slot),
          onLongPress: () => _dj.clearHotcue(i, slot),
        );
      case PadMode.loop:
        final beats = _loopSizes[slot];
        final current = d.loopBars * 4;
        final on = d.loopEnabled && (current - beats).abs() < 0.05;
        return _pad(
          color: SideDeckTheme.loop,
          filled: on,
          enabled: d.loaded,
          label: beats < 1 ? '1/${(1 / beats).round()}' : '${beats.round()}',
          onTap: () => _dj.setLoop(i, !on, beats / 4.0),
        );
      case PadMode.jump:
        final b = _jumpSizes[slot];
        return _pad(
          color: SideDeckTheme.accent(i),
          filled: false,
          enabled: d.loaded,
          label: b < 0 ? '◀ ${-b}' : '$b ▶',
          onTap: () => _dj.beatJump(i, b),
        );
    }
  }

  Widget _pad({
    required Color color,
    required bool filled,
    required bool enabled,
    required String label,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
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
          color: filled && enabled ? color : const Color(0xFF17181C),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: filled && enabled ? color : SideDeckTheme.stroke,
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
            color: filled ? Colors.black : SideDeckTheme.text,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ mixer

  Future<void> _openMixer() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SideDeckTheme.panel,
      builder: (ctx) => AnimatedBuilder(
        animation: _dj,
        builder: (ctx, _) => SizedBox(
          height: 170,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: MixerStrip(
              controller: _dj,
              onLibrary: () {
                Navigator.pop(ctx);
                _openLibrary();
              },
              onSettings: () {
                Navigator.pop(ctx);
                _openSettings();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBar() {
    return Material(
      color: const Color(0xFF5C1A1A),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF8A80)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _dj.engineError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFFCDD2)),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              onPressed: _dj.clearError,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridEditorBar(int deck, Color accent) {
    Widget step(String label, VoidCallback onStep) {
      return HoldRepeatButton(
        onStep: onStep,
        child: Container(
          width: 36,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SideDeckTheme.panelAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withValues(alpha: 0.8)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1),
          ),
        ),
      );
    }

    return Material(
      color: const Color(0xE0101114),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            step('«', () => _dj.shiftGridBeats(deck, -1)),
            const SizedBox(width: 4),
            step('»', () => _dj.shiftGridBeats(deck, 1)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('beat · 5 ms', style: TextStyle(fontSize: 9, color: SideDeckTheme.muted)),
            ),
            step('‹', () => _dj.shiftGridMs(deck, -5)),
            const SizedBox(width: 4),
            step('›', () => _dj.shiftGridMs(deck, 5)),
          ],
        ),
      ),
    );
  }
}

enum PadMode { hotcue, loop, jump }

class _XfaderThumb extends SliderComponentShape {
  const _XfaderThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(22, 44);

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
      Rect.fromCenter(center: center, width: 22, height: 44),
      const Radius.circular(5),
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
      Offset(center.dx, center.dy - 8),
      Offset(center.dx, center.dy + 8),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 2,
    );
  }
}
