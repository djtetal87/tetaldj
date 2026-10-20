/// Marker library for the TetalDJ native engine FFI plugin.
///
/// The engine's symbols (`dj_create`, `dj_load`, ...) are linked into the app
/// binary by the iOS pod in `ios/tetaldj_engine.podspec`; the Dart side
/// reaches them through `DynamicLibrary.process()` in `lib/engine/`.
library;
