// Renders the main screen with two loaded tracks and saves a PNG, so the
// layout can be checked without a phone. Needs the engine preloaded:
//   LD_PRELOAD=libdj_shared.so flutter test test/screenshot_test.dart
// Skipped unless TETALDJ_SHOT points at an output path.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidedeck/state/dj_controller.dart';
import 'package:sidedeck/state/library_controller.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';
import 'package:sidedeck/ui/home_page.dart';

void main() {
  final out = Platform.environment['TETALDJ_SHOT'];
  final tracks = Platform.environment['TETALDJ_TRACKS']?.split(':') ?? const [];
  final size = (Platform.environment['TETALDJ_SIZE'] ?? '852x393').split('x');

  testWidgets('home screen screenshot', (tester) async {
    if (out == null) return;
    tester.view.physicalSize =
        Size(double.parse(size[0]), double.parse(size[1]));
    tester.view.devicePixelRatio = 1.0;

    final dj = DjController();
    final library = LibraryController();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: SideDeckTheme.dark(),
        home: RepaintBoundary(
          key: key,
          child: HomePage(dj: dj, library: library),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < tracks.length && i < 2; i++) {
        final name = tracks[i].split('/').last.replaceAll('.wav', '');
        final parts = name.split(' - ');
        await dj.loadFile(
          i,
          tracks[i],
          title: parts.first,
          artist: parts.length > 1 ? parts.last : 'DJ Tetal',
        );
      }
      dj.clearError();
      if (tracks.isNotEmpty) {
        // Some state to look at: cues, a loop, a sync, a position.
        dj.seekTo(0, 42.0);
        dj.hotcue(0, 0);
        dj.seekTo(0, 48.0);
        dj.hotcue(0, 1);
        dj.seekTo(0, 56.0);
        dj.hotcue(0, 2);
        dj.seekTo(0, 61.3);
        dj.playPause(0);
        if (tracks.length > 1) {
          dj.seekTo(1, 20.0);
          dj.hotcue(1, 0);
          dj.seekTo(1, 33.5);
          dj.sync(1);
          dj.setLoop(1, true, 1.0);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(out).writeAsBytes(bytes!.buffer.asUint8List());
    });
    dj.dispose();
    library.dispose();
  });
}
