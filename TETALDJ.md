# TetalDJ — fork de SideDeck

Base: [manueljpy/SideDeck](https://github.com/manueljpy/SideDeck) (GPL-3.0-or-later).
Flutter (Dart UI) + motor C++ (Oboe) vía FFI. Solo Android por ahora.

## Cambios respecto a upstream

### v0.1 — CUE y hot cues en pantalla (2026-10-20)
Upstream tenía cue/hot cues implementados en el motor C++ pero sin exponer al
Dart ni a la UI. Ahora:

- `native/engine/dj_engine.{h,cpp}`: `dj_set_cue_at` y `dj_get_cue` (fijar/leer
  el cue principal en segundos, para restaurarlo desde disco).
- `lib/engine/native_engine.dart`: bindings FFI de `dj_set_cue`, `dj_jump_cue`,
  `dj_set_cue_at`, `dj_get_cue`, `dj_set_hotcue`, `dj_jump_hotcue`,
  `dj_get_hotcue`, `dj_clear_hotcue`.
- `lib/engine/hotcue_store.dart` (nuevo): SQLite propio (`tetaldj_cues.db`)
  con cue + 4 hot cues por ruta de archivo. Independiente de la caché de
  análisis para que un re-análisis no borre los cues.
- `lib/state/dj_controller.dart`: `cue()`, `cuePlay()`, `hotcue()`,
  `clearHotcue()`, campos `cuePoint`/`hotcues` en `DeckState`, y restauración
  de cues al cargar un track.
- `lib/ui/waveform.dart`: marcadores en la onda (overview y zoom) — cue en
  blanco, hot cues con colores Serato (rojo, naranjo, amarillo, verde) y
  etiqueta numerada.
- `lib/ui/home_page.dart`: fila de pads `CUE 1 2 3 4` bajo el título del deck.

Comportamiento (tipo Serato / Virtual DJ):
- CUE pausado → fija el cue en el playhead. CUE tocando → vuelve al cue y para.
  Mantener CUE → salta al cue y reproduce.
- Pad vacío → fija el hot cue en el playhead. Pad lleno → salta (y reproduce si
  estaba pausado). Mantener pad → borra.

## Compilar
```
flutter pub get
flutter run -d <android-device>      # o: flutter build apk --debug
```
`flutter analyze` y `flutter test` pasan. El C++ se compila con el NDK al hacer
`flutter run`; no fue compilado en este entorno.

## Roadmap propuesto
1. [x] CUE + hot cues en UI, con persistencia
2. [ ] Platos / jog wheel táctil (scratch + pitch bend por arrastre) — requiere
       `dj_scratch(deck, velocity)` en el motor (hoy solo hay nudge por rate)
3. [ ] FX por deck: echo, reverb, flanger, roll — bloque `biquad.hpp` ya
       existe; agregar DSP en `dj_engine.cpp` antes del EQ
4. [ ] Grabación de la mezcla a WAV/MP3 (tap del bus master en el callback)
5. [ ] Modo vertical (teléfono en portrait, un deck arriba y otro abajo)
6. [ ] Rebranding: nombre, package `es.manifold.sidedeck` → `cl.tetal.tetaldj`,
       ícono, colores
7. [ ] iOS: backend Core Audio / AVAudioEngine (o miniaudio) para reemplazar
       Oboe; Flutter ya cubre la UI
