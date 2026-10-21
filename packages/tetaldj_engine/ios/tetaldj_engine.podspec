#
# TetalDJ native engine for iOS. The static library is produced by CMake
# (see native/CMakeLists.txt) and copied next to this file before
# `flutter build ios` runs. -force_load keeps every dj_* symbol in the
# framework even though no Objective-C code references them, so Dart FFI
# can find them through DynamicLibrary.process().
#
Pod::Spec.new do |s|
  s.name             = 'tetaldj_engine'
  s.version          = '0.1.0'
  s.summary          = 'TetalDJ native DJ engine (C++ / miniaudio / ONNX Runtime).'
  s.description      = 'Two-deck DJ audio engine with time-stretch, EQ, filter, loops and hot cues.'
  s.homepage         = 'https://github.com/djtetal87/tetaldj'
  s.license          = { :type => 'GPL-3.0-or-later', :file => '../../../LICENSE' }
  s.author           = { 'DJ Tetal' => 'djtetaloficial@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.vendored_libraries = 'libtetaldj_engine.a'
  # ONNX Runtime (stems inference). The static xcframework is downloaded by
  # the iOS workflow from download.onnxruntime.ai (pod-archive-onnxruntime-c)
  # and vendored here, so it links into this dynamic framework.
  s.vendored_frameworks = 'onnxruntime.xcframework'
  s.weak_frameworks  = 'CoreML'
  s.preserve_paths   = 'libtetaldj_engine.a', 'onnxruntime.xcframework'
  s.libraries        = 'c++'
  s.frameworks       = 'CoreAudio', 'AudioToolbox', 'AVFoundation', 'CoreFoundation'
  s.platform         = :ios, '15.0'
  s.dependency 'Flutter'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load "$(PODS_TARGET_SRCROOT)/libtetaldj_engine.a"',
  }
  s.swift_version = '5.0'
end
