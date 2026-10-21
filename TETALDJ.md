# TetalDJ — fork de SideDeck

Base: [manueljpy/SideDeck](https://github.com/manueljpy/SideDeck) (GPL-3.0-or-later).
Flutter (Dart UI) + motor C++ vía FFI. Android (Oboe) e iOS (miniaudio / Core Audio).

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

### v0.2 — port a iOS + .ipa por GitHub Actions (2026-10-20)
El motor era solo Android (Oboe, logcat, MediaCodec). Ahora compila también
para iOS / macOS / Linux:

- `native/engine/platform_log.hpp`: LOGI/LOGE → logcat en Android, stderr en
  el resto (reemplaza `<android/log.h>` en `dj_engine.cpp` y `chunk_cache.hpp`).
- `native/engine/dj_engine.cpp`: `struct Engine` tiene dos backends de salida
  bajo `#ifdef __ANDROID__`: Oboe (igual que upstream) o **miniaudio**
  (`ma_device`, Core Audio en iPhone, 48 kHz / 256 frames, misma
  `renderInterleaved`). El modo mixer USB 4 canales queda solo en Android.
- `native/engine/audio_backend_miniaudio.cpp` + `third_party/miniaudio/`
  (v0.11.25, MIT-0/public domain). En Apple se compila como Objective-C++
  porque miniaudio usa AVAudioSession.
- AAC/M4A: upstream ya lo tenía bajo `__ANDROID__` (MediaCodec), así que en
  iOS por ahora van MP3, WAV, FLAC y Opus. AudioToolbox para AAC: pendiente.
- `native/CMakeLists.txt` (nuevo): build estático del motor + qm-dsp + opus
  para iOS/macOS/Linux, y en Apple une todo en `libtetaldj_engine.a`.
  Probado en Linux: compila, analiza BPM (124.00 en un click de 124) y carga
  pistas con el backend Null de miniaudio.
- `ios/` (nuevo, `flutter create`): bundle `cl.tetal.tetaldj`, nombre
  "TetalDJ", solo horizontal, audio en segundo plano, compartir archivos
  (`UIFileSharingEnabled`) para soltar MP3 desde Finder / app Archivos.
- `packages/tetaldj_engine/` (nuevo): plugin FFI de Flutter cuyo podspec
  vendoriza `libtetaldj_engine.a` con `-force_load`, para que
  `DynamicLibrary.process()` encuentre los `dj_*`.
- `lib/state/library_controller.dart`: en iOS la librería es
  `Documents/Music` y los archivos elegidos con el picker se copian ahí
  (el picker de iOS entrega copias temporales que el sistema borra).
- `.github/workflows/ios.yml`: igual que TetalCut — runner macOS, CMake
  cruzado a arm64, `flutter build ios --no-codesign`, y sube
  `TetalDJ-<versión>-ios-arm64.ipa` como artifact para Sideloadly.

## Compilar
```
flutter pub get
flutter run -d <android-device>      # o: flutter build apk --debug
```
`flutter analyze` y `flutter test` pasan. El C++ de Android se compila con el
NDK al hacer `flutter run`; no fue compilado en este entorno.

### iPhone (.ipa sin firmar, para Sideloadly)
1. Crear el repo `djtetal87/tetaldj` en GitHub y subir este proyecto.
2. GitHub → Actions → **Build for iPhone** → Run workflow.
3. Descargar el artifact `TetalDJ-ios-arm64`, descomprimir el .ipa.
4. Sideloadly: iPhone conectado, arrastrar el .ipa, Apple ID, Start.
   (Certificado gratis: la app caduca a los 7 días; se vuelve a instalar.)
5. Para cargar música: Finder → iPhone → Archivos → TetalDJ → soltar los MP3
   en `Music`, o desde la app con "elegir archivos".

Primera vez que corre el workflow puede fallar en algo de CocoaPods / Xcode
que no se puede probar fuera de macOS: el log queda en el summary del run.

## Roadmap propuesto
1. [x] CUE + hot cues en UI, con persistencia
1b. [x] Port del motor a iOS (miniaudio) + workflow de .ipa
2. [ ] Platos / jog wheel táctil (scratch + pitch bend por arrastre) — requiere
       `dj_scratch(deck, velocity)` en el motor (hoy solo hay nudge por rate)
3. [ ] FX por deck: echo, reverb, flanger, roll — bloque `biquad.hpp` ya
       existe; agregar DSP en `dj_engine.cpp` antes del EQ
4. [ ] Grabación de la mezcla a WAV/MP3 (tap del bus master en el callback)
5. [ ] Modo vertical (teléfono en portrait, un deck arriba y otro abajo)
6. [ ] Rebranding: nombre, package `es.manifold.sidedeck` → `cl.tetal.tetaldj`,
       ícono, colores
7. [ ] iOS: AAC/M4A con AudioToolbox; ícono y launch screen propios

### v0.3 — UI handheld estilo Serato, grabación y efectos (2026-10-20)
- Ícono con el logo "Cesar Augusto"; applicationId `cl.tetal.tetaldj`.
- Pantalla nueva (`lib/ui/home_page.dart`, `lib/ui/platter.dart`): barra
  superior con cargar / título / mini-onda / key, platos táctiles en modo
  vinilo (tocar detiene, arrastrar mueve, soltar sigue), fader VOL/BPM
  (±16 %) con botón KEY lock, ondas A y B apiladas al centro, transporte
  (mixer, PLAY, CUE, SYNC, LOOP), crossfader y pads de 4 con dos páginas y
  modos HOT CUES / AUTO LOOP / BEAT JUMP / FX.
- Onda a 3 colores: `scanWaveform` calcula energía <200 Hz / 200 Hz-2 kHz /
  >2 kHz por bin (`dj_waveform_bands_copy`); rojo graves, verde medios,
  azul agudos. Hot cues de 4 a 8; loops desde 1/4 de beat.
- Grabación (`native/engine/mix_recorder.hpp`): bus master a WAV 16-bit
  en `Documents/Grabaciones`, ring buffer + hilo escritor; botón REC.
- Efectos (`native/engine/deck_fx.hpp`): insert por deck después de
  EQ/filtro — echo sincronizado, reverb (Freeverb), flanger, phaser,
  crusher y gate; `dj_set_fx(deck, type, amount, beats)`. En la UI, pad
  mode FX enciende/apaga; mantener un pad abre intensidad y tiempo.
- `test/screenshot_test.dart` renderiza la pantalla a PNG con el motor
  precargado (`LD_PRELOAD`), para revisar el layout sin teléfono.

### v0.3.1 — scratch real en el plato (2026-10-20)
- Motor: `dj_scratch_begin/rate/end`. Mientras el plato está tocado el deck
  deja de reproducir y lee del caché a la velocidad de la mano (frames por
  frame, negativa hacia atrás), con suavizado por bloque, EQ/filtro/fader
  aplicados; al soltar re-prima el stretcher en la nueva posición.
- Plato: velocidad angular con los timestamps del puntero (una vuelta =
  1,8 s); 70 ms sin movimiento = mano quieta = silencio.

### v0.3.2 — onda sigue el scratch, freno de vinilo, colas de FX (2026-10-20)
- `_tick` actualiza la posición también mientras el plato está activo
  (`dj_platter_active`), así la onda y el plato giran hacia atrás al hacer
  scratch.
- `dj_brake`: PLAY sobre un tema sonando frena como un motor de tornamesa
  (~0,8 s, con caída de tono) en vez de cortar; PLAY durante el freno
  retoma desde donde va. CUE y el toque del plato siguen siendo instantáneos.
- Los efectos se procesan aunque el deck esté en silencio o con el fader
  abajo: las colas de echo/reverb se apagan solas.

### v0.4 — stems (2026-10-20)
- `assets/models/spleeter4.fp16.onnx`: los cuatro U-Net de Spleeter 4stems
  (deezer/spleeter v1.4.0, MIT) convertidos a ONNX en un solo archivo fp16
  (79 MB); conversión verificada contra el grafo TF (diferencia < 1e-4).
  Script de conversión: `tools/stems/` (unet4.py + convert4.py).
- `native/engine/stem_separator.cpp`: decodifica, remuestrea a 44,1 kHz,
  STFT 4096/1024 (Hann periódica), máscaras ratio con exponente 2, iSTFT
  con overlap-add, y suma el residuo (>11 kHz y bordes) a "other" para que
  los cuatro stems sumen exactamente el original. Escribe 4 WAV 16-bit.
  Corre con ONNX Runtime (2 hilos); ~0,08x tiempo real en x86.
- Motor: `Deck::read` mezcla cuatro `ChunkCache` (vocals/drums/bass/other)
  por ganancia en vez del caché principal cuando los stems están activos;
  `dj_stems_separate/progress/state/cancel/error`, `dj_stems_attach/detach`,
  `dj_set_stem_gain`. En Android se compila con `TETALDJ_NO_ORT` (sin stems).
- App: modo STEMS en los pads. Sin preparar: PREPARAR corre la separación en
  un isolate con progreso; luego los cuatro pads silencian/activan cada stem
  (mantener uno apaga el modo stems). Caché en
  `Library/Application Support/stems/<sha1(ruta|tamaño)>/`.
- iOS: el pod `onnxruntime-c` 1.20.0 va como dependencia del plugin FFI.
