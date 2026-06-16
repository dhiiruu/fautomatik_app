cmake_minimum_required(VERSION 3.10)
project(vulkan_compute_engine)

# Vulkan headers from NDK
find_path(VULKAN_INCLUDE_DIR vulkan/vulkan.h
    PATHS
        ${ANDROID_NDK}/sysroot/usr/include
        ${CMAKE_SYSROOT}/usr/include
    NO_DEFAULT_PATH
)
if(NOT VULKAN_INCLUDE_DIR)
    set(VULKAN_INCLUDE_DIR "${ANDROID_NDK}/sysroot/usr/include")
endif()

message(STATUS "Vulkan include: ${VULKAN_INCLUDE_DIR}")

# ── opencv-mobile (minimal OpenCV build) ─────────────────────────────
# Only builds core + imgproc + imgcodecs + support libs.
# Equivalent to nihui/opencv-mobile configuration.
include(FetchContent)

set(OPENCV_VERSION 4.9.0)

# Disable all modules by default, enable only what we need
set(BUILD_opencv_core ON CACHE BOOL "" FORCE)
set(BUILD_opencv_imgproc ON CACHE BOOL "" FORCE)
set(BUILD_opencv_imgcodecs ON CACHE BOOL "" FORCE)
set(BUILD_opencv_calib3d OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_dnn OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_features2d OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_flann OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_gapi OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_highgui OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_java OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_java_bindings OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_js OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_ml OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_objdetect OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_photo OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_python OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_python_bindings OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_stitching OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_ts OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_video OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_videoio OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_world OFF CACHE BOOL "" FORCE)

# Image codec support
set(WITH_JPEG ON CACHE BOOL "" FORCE)
set(WITH_PNG ON CACHE BOOL "" FORCE)
set(WITH_TIFF OFF CACHE BOOL "" FORCE)
set(WITH_WEBP OFF CACHE BOOL "" FORCE)
set(WITH_OPENJPEG OFF CACHE BOOL "" FORCE)
set(WITH_JASPER OFF CACHE BOOL "" FORCE)
set(WITH_OPENEXR OFF CACHE BOOL "" FORCE)

# Build as static libs
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_opencv_apps OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_PERF_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_DOCS OFF CACHE BOOL "" FORCE)

# Disable NEON for armeabi-v7a if needed (OpenCV handles this)
# Disable unwanted 3rd party
set(BUILD_ITT OFF CACHE BOOL "" FORCE)
set(WITH_ITT OFF CACHE BOOL "" FORCE)
set(WITH_LAPACK OFF CACHE BOOL "" FORCE)
set(WITH_MF OFF CACHE BOOL "" FORCE)
set(WITH_MSMF OFF CACHE BOOL "" FORCE)
set(WITH_OBSENSOR OFF CACHE BOOL "" FORCE)
set(WITH_OPENCL OFF CACHE BOOL "" FORCE)
set(WITH_OPENGL OFF CACHE BOOL "" FORCE)
set(WITH_OPENVX OFF CACHE BOOL "" FORCE)
set(WITH_PROTOBUF OFF CACHE BOOL "" FORCE)
set(WITH_PTHREADS_PF ON CACHE BOOL "" FORCE)
set(WITH_QUIRC OFF CACHE BOOL "" FORCE)
set(WITH_VULKAN OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    opencv
    GIT_REPOSITORY https://github.com/opencv/opencv.git
    GIT_TAG ${OPENCV_VERSION}
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(opencv)

# ── Engine source files ──────────────────────────────────────────────
file(GLOB ENGINE_SOURCES
    "src/main/cpp/vulkan_engine.cpp"
    "src/main/cpp/native_image.cpp"
    "src/main/cpp/texture_bridge_jni.cpp"
    "src/main/cpp/tensor_staging.cpp"
)

file(GLOB SPIRV_HEADERS
    "src/main/cpp/shaders/spv/*.h"
)

# ── Shared library ───────────────────────────────────────────────────
add_library(vulkan_compute_engine SHARED
    ${ENGINE_SOURCES}
    ${SPIRV_HEADERS}
)

target_include_directories(vulkan_compute_engine
    PRIVATE
        ${VULKAN_INCLUDE_DIR}
        src/main/cpp
        ${opencv_SOURCE_DIR}/include
)

target_link_libraries(vulkan_compute_engine
    log
    android
    opencv_core
    opencv_imgproc
    opencv_imgcodecs
    libjpeg-turbo
    libpng
    zlib
)

target_compile_features(vulkan_compute_engine PUBLIC cxx_std_17)

target_compile_options(vulkan_compute_engine PRIVATE
    -O3
    -fvisibility=hidden
    -ffast-math
)
