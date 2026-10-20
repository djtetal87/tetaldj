# TetalDJ native engine for iOS / macOS / Linux (Android keeps building
# through android/app/src/main/cpp/CMakeLists.txt with Oboe).
#
#   cmake -S native -B build/native-ios -G Xcode \
#         -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
#   cmake --build build/native-ios --config Release
#
# Produces a static libdj_engine.a plus its dependencies; the FFI plugin in
# packages/tetaldj_engine links them into the Flutter app.
cmake_minimum_required(VERSION 3.22)
project(dj_engine VERSION 1.0.0 LANGUAGES C CXX)
if(APPLE)
  # miniaudio's Core Audio backend uses AVAudioSession (Objective-C) on iOS,
  # so its implementation unit must be compiled as Objective-C++.
  enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

get_filename_component(TETALDJ_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(ENGINE_DIR "${TETALDJ_ROOT}/native/engine")
set(THIRD "${TETALDJ_ROOT}/third_party")

add_subdirectory("${THIRD}/qm-dsp" qm-dsp-build)
include("${THIRD}/opus_stack.cmake")

add_library(dj_engine STATIC
  "${ENGINE_DIR}/dj_engine.cpp"
  "${ENGINE_DIR}/last_error.cpp"
  "${ENGINE_DIR}/audio_backend_miniaudio.cpp"
)
if(APPLE)
  set_source_files_properties("${ENGINE_DIR}/audio_backend_miniaudio.cpp"
    PROPERTIES LANGUAGE OBJCXX COMPILE_FLAGS "-fobjc-arc")
endif()
target_compile_definitions(dj_engine PRIVATE _USE_MATH_DEFINES)
target_compile_options(dj_engine PRIVATE -fexceptions)
target_include_directories(dj_engine PRIVATE
  "${ENGINE_DIR}"
  "${THIRD}/dr_libs"
  "${THIRD}/signalsmith-stretch"
  "${THIRD}/signalsmith-linear/include"
  "${THIRD}/qm-dsp"
  "${THIRD}/miniaudio"
)
target_link_libraries(dj_engine PUBLIC qm_dsp opusfile)

if(APPLE)
  target_link_libraries(dj_engine PUBLIC
    "-framework CoreAudio" "-framework AudioToolbox" "-framework AVFoundation"
    "-framework CoreFoundation")
elseif(UNIX)
  target_link_libraries(dj_engine PUBLIC pthread dl m)
endif()

# One merged archive so the iOS pod only has to vendor a single file.
set(MERGED "${CMAKE_BINARY_DIR}/libtetaldj_engine.a")
if(APPLE)
  add_custom_command(OUTPUT "${MERGED}"
    COMMAND libtool -static -o "${MERGED}"
            $<TARGET_FILE:dj_engine> $<TARGET_FILE:qm_dsp> $<TARGET_FILE:opusfile>
            $<TARGET_FILE:ogg> $<TARGET_FILE:opus>
    DEPENDS dj_engine qm_dsp opusfile ogg opus
    COMMENT "Merging static libraries into libtetaldj_engine.a")
  add_custom_target(tetaldj_engine_merged ALL DEPENDS "${MERGED}")
endif()
