import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidedeck/engine/usb_output.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/state/library_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/deck_header.dart';
import 'package:sidedeck/ui/deck_pads.dart';
import 'package:sidedeck/ui/library_drawer.dart';
import 'package:sidedeck/ui/mixer_strip.dart';
import 'package:sidedeck/ui/settings_page.dart';
import 'package:sidedeck/ui/waveform.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DjController _dj;
  late final LibraryController _library;
  int? _gridEditDeck;
  final _padMode = [PadMode.hotcue, PadMode.hotcue];
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
    _dj = DjController();
    _library = LibraryController();
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
                Expanded(child: _deckBlock(0)),
                const SizedBox(height: 3),
                Expanded(child: _deckBlock(1)),
                const SizedBox(height: 4),
                _performancePanel(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ decks

  Widget _deckBlock(int i) {
    final d = _dj.deck(i);
    final accent = SideDeckTheme.accent(i);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          DeckHeader(
            deck: i,
            state: d,
            dj: _dj,
            gridEditing: _gridEditDeck == i,
            onToggleGrid: () =>
                setState(() => _gridEditDeck = _gridEditDeck == i ? null : i),
            onLoad: _openLibrary,
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
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
                    zoom: 6,
                    onSeek: d.loaded ? (t) => _dj.seek(i, t) : null,
                    onOverviewSeek: d.loaded ? (t) => _dj.seekTo(i, t) : null,
                  ),
                  if (!d.loaded)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openLibrary,
                        child: Center(
                          child: Text(
                            'DECK ${i == 0 ? 'A' : 'B'}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: accent.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_gridEditDeck != null && _gridEditDeck != i)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _gridEditDeck = null),
                      ),
                    ),
                  if (d.loaded && _gridEditDeck == i)
                    Positioned(
                      left: 6,
                      bottom: 4,
                      child: _gridEditorBar(i, accent),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ performance

  Widget _performancePanel() {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        children: [
          DeckPads(
            deck: 0,
            dj: _dj,
            mode: _padMode[0],
            onMode: (m) => setState(() => _padMode[0] = m),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MixerStrip(
              controller: _dj,
              onLibrary: _openLibrary,
              onSettings: _openSettings,
            ),
          ),
          const SizedBox(width: 8),
          DeckPads(
            deck: 1,
            dj: _dj,
            mode: _padMode[1],
            onMode: (m) => setState(() => _padMode[1] = m),
          ),
        ],
      ),
    );
    return SizedBox(
      height: 150,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: SideDeckTheme.panel,
          border: Border(top: BorderSide(color: SideDeckTheme.stroke)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (_gridEditDeck != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _gridEditDeck = null),
                ),
              ),
          ],
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
          width: 44,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SideDeckTheme.panelAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withValues(alpha: 0.8)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      );
    }

    Widget pair(String caption, Widget left, Widget right) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          left,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              caption,
              style: const TextStyle(fontSize: 10, color: SideDeckTheme.muted),
            ),
          ),
          right,
        ],
      );
    }

    return Material(
      color: const Color(0xE0101114),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GRID',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: SideDeckTheme.muted,
              ),
            ),
            const SizedBox(width: 10),
            pair(
              'beat',
              step('«', () => _dj.shiftGridBeats(deck, -1)),
              step('»', () => _dj.shiftGridBeats(deck, 1)),
            ),
            const SizedBox(width: 12),
            pair(
              '5 ms',
              step('‹', () => _dj.shiftGridMs(deck, -5)),
              step('›', () => _dj.shiftGridMs(deck, 5)),
            ),
          ],
        ),
      ),
    );
  }
}
