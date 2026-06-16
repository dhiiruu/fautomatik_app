# Fautomatik App - Codebase Understanding

## Overview

**Fautomatik** is a high-performance Flutter-based AI photo editing and photo booth application designed for Android devices (targeting mid-range hardware like Redmi Note 10, Android 12). The app provides guided selfie capture with face/body detection, document scanning, and a comprehensive suite of AI-powered photo editing tools.

---

## Architecture Philosophy

### Zero-Copy Native Processing

The core architectural innovation is avoiding the "Dart copy tax" - traditional Flutter apps serialize image data through `Uint8List` or `MethodChannels`, causing:
- **GC spikes** from constant heap allocation/deallocation
- **CPU bottlenecks** from copying large arrays (e.g., 48MB for a 12MP image)

**Solution**: Images live in native C++ memory as `cv::Mat` objects. Dart holds only a 64-bit pointer handle, passing it via FFI to:
- Vulkan compute shaders (GPU)
- ONNX Runtime Mobile (AI models)
- Flutter TextureRegistry (display)

### Dual-Track Input Architecture

1. **Master State Buffer**: High-resolution native image (`NativeImg`) stays at original camera resolution for display and traditional filters
2. **Dynamic Sub-Tensor Generation**: AI models receive downsampled volatile copies routed to pre-allocated staging buffers with model-specific dimensions and normalization

---

## Technology Stack

### Frontend (Flutter/Dart)
- **State Management**: Riverpod
- **Local Storage**: Hive (for session/unlock state)
- **Camera**: `camera` package
- **ML/AI**: 
  - `flutter_onnxruntime` - background removal (U2Net), face detection (YuNet)
  - `face_detection_tflite` - MediaPipe face mesh (468 landmarks)
  - `google_mlkit_pose_detection` - body pose estimation
- **PDF/Print**: `pdf`, `printing` packages
- **Monetization**: `google_mobile_ads` (rewarded ads for unlock)

### Native Layer (C++)
- **OpenCV (opencv-mobile)**: Image processing, color conversion, resizing
- **Vulkan Compute**: GPU-accelerated shaders for grayscale, brightness/contrast, compositing
- **ONNX Runtime Mobile**: Model inference with FP16 precision
- **Android NDK**: `AHardwareBuffer`, `ANativeWindow` for zero-copy texture display

### Hardware Acceleration Mapping

| Operation | Target Hardware | Mechanism |
|-----------|----------------|-----------|
| Face/Body Detection (MediaPipe, YOLO) | NPU | Android NNAPI / Qualcomm QNN |
| Background Removal, Segmentation (U2Net, MobileSAM) | GPU | Vulkan/OpenGL ES, FP16 |
| Traditional Filters (brightness, contrast, blend) | GPU | Fragment shaders |
| Pre-processing (rotation, normalization, Exif) | CPU | Multi-threaded OpenCV |

---

## Core Components

### Native Image System (`lib/compute/cv.dart`, `android/app/src/main/cpp/native_image.*`)

```dart
final class NativeImg {
  int _handle; // 64-bit pointer to cv::Mat in C++ heap
  
  static NativeImg? decode(Uint8List bytes);
  static NativeImg? fromFile(String path);
  static NativeImg? create(int w, int h);
  static NativeImg? fromRgba(Uint8List pixels, int w, int h);
  
  // In-place operations (no Dart heap copy)
  bool cvtColor(int code);
  bool resize(int w, int h, {int interpolation = 1});
  bool gaussianBlur(int kx, int ky, ...);
  
  // Zero-copy access
  Pointer<Uint8>? get data;
}
```

### Tensor Staging Bridge (`lib/compute/ai_staging_bridge.dart`, `tensor_staging.h/cpp`)

Pre-allocated Float32 buffers for AI model input with lazy dimension binding:

```dart
final staging = AIStagingManager();

// Configure slot for U2Net (320×320, ImageNet normalization)
staging.initModelSlot(
  slotId: 0,
  width: 320, height: 320, channels: 3,
  mean: [0.485, 0.456, 0.406],
  stdDev: [0.229, 0.224, 0.225],
  isPlanarCHW: true,
);

// On inference:
staging.populateSlotInput(nativeImgHandle, slotId: 0);
final ptr = staging.getInputPointer(slotId: 0);
// Pass ptr directly to ONNX Runtime
```

### Vulkan Compute Engine (`lib/compute/vulkan_bridge.dart`, `vulkan_engine.h/cpp`)

Low-level FFI bindings for GPU compute shaders:
- Grayscale conversion
- Brightness/contrast adjustment
- Alpha compositing (background replacement)

### Texture Display (`lib/compute/native_texture_controller.dart`, `texture_bridge_jni.cpp`)

Zero-copy rendering pipeline:
```dart
final ctrl = NativeTextureController(nativeImgHandle: img.handle);
await ctrl.initialize(); // Creates Android SurfaceTexture
// In build:
ctrl.view // → Texture(textureId: ...)
await ctrl.updateDisplay(); // Pushes native pixels via JNI
```

---

## Feature Modules

### Camera Modes

1. **Photo Booth (Guided Camera)**
   - Real-time face mesh + body pose detection
   - Auto-capture when subject is stable (~1.5s)
   - Audio guidance via TTS
   - Overlays: face oval, eye line, body skeleton, auto-capture ring

2. **Standard Camera**
   - Minimal point-and-shoot interface
   - No ML overlays

3. **Scan Camera**
   - Document scanning with edge detection
   - Auto-crop via perspective warp
   - Grid overlay for alignment

### Editing Pipeline

Features implemented as standalone screens with shared pipeline architecture:

| Feature | Description |
|---------|-------------|
| Magic Portrait | One-tap portrait enhancement |
| Remove BG | U2Net background removal |
| Auto Crop | Face-guided cropping |
| Straighten | Head tilt correction |
| Auto Lighting | Brightness/shadow balancing |
| Sharpen | Smart sharpening |
| Skin Smooth | Blemish reduction |
| Red-Eye Fix | Auto detection & correction |
| BG Color | Solid color background replacement |
| Border | Inner/outer, dashed/solid borders |
| Resize | Dimension scaling |
| Convert Format | PNG/JPG/WEBP conversion |
| Print Template | Multi-photo layout optimization |

### Print Template Engine

- Paper sizes: 4×6", 5×7", 6×8", A4, A5
- DPI settings: 72-1200 (recommends 300)
- Auto-arrangement with rotation for maximum paper usage
- PDF export with crop marks
- Direct printing via system dialog

---

## Data Flow Example: Remove Background

```
[User selects photo]
        ↓
[NativeImg.decode(bytes)] → cv::Mat in C++ heap (handle: 0x7FFF)
        ↓
[AIStagingManager.populateSlotInput(handle, slotId: 0)]
  - Downsamples master image to 320×320
  - Applies ImageNet normalization
  - Writes to pre-allocated Float32 buffer
        ↓
[ONNX Runtime inference]
  - Reads directly from staging buffer pointer
  - Returns mask tensor
        ↓
[VulkanBridge.processComposite()]
  - Upscales mask to original resolution
  - Composites with user-selected background color
  - All operations on GPU via fragment shaders
        ↓
[NativeTextureController.updateDisplay()]
  - Pushes result to Flutter Texture widget
        ↓
[User sees result in <100ms]
```

---

## UI/UX Design

### Visual Style
- **Theme**: Dark mode with deep purple (#7C4DFF) accent
- **Background**: Near-black (#0D0D0D)
- **Cards**: #1A1A2E with subtle borders (#2A2A4E)
- **Typography**: Light sans-serif (300/400 weight), monospace for dimensions
- **Motion**: 300ms ease-in-out, slide-up transitions
- **Haptics**: Light impact on card tap, heavy on capture

### Key Screens
1. **Home**: 3 camera mode cards + edit tools grid
2. **Guided Camera**: Full-screen preview with overlay painter
3. **Template/Print**: PageView of layouts with collapsible config panel
4. **Photo Preview Sheet**: Bottom sheet with Edit/Retake/Layout actions

---

## Session Management

### Unlock System
- App locks after period of inactivity
- Users watch rewarded ad to unlock for 2 hours
- Uses NTP time sync to prevent clock manipulation
- HMAC-signed unlock records stored in Hive

```dart
// lib/services/unlock_service.dart
// lib/storage/session_store.dart
```

---

## File Structure

```
/workspace
├── lib/
│   ├── main.dart                    # App entry, Riverpod setup
│   ├── core/
│   │   ├── app_theme.dart           # ThemeData, colors
│   │   ├── pipeline.dart            # InferencePipeline orchestrator
│   │   └── types.dart               # Data classes (FaceData, BodyData)
│   ├── compute/
│   │   ├── cv.dart                  # NativeImg, dartcv4 wrappers
│   │   ├── vulkan_bridge.dart       # Vulkan FFI bindings
│   │   ├── ai_staging_bridge.dart   # Tensor staging manager
│   │   └── native_texture_controller.dart  # Texture display
│   ├── features/
│   │   ├── home/home_screen.dart    # Main menu
│   │   ├── photo_booth/             # Guided camera flow
│   │   ├── camera/                  # Camera engine wrapper
│   │   ├── scanner/                 # Document scanning
│   │   ├── edit/                    # Photo editor pipeline
│   │   ├── print_template/          # Layout engine, PDF export
│   │   └── [feature]/               # Individual edit tools
│   ├── services/
│   │   ├── unlock_service.dart      # Ad-based unlock logic
│   │   ├── unlock_notifier.dart     # Provider notifications
│   │   └── ad_service.dart          # AdMob integration
│   ├── shared/
│   │   ├── face/                    # Face pipeline abstraction
│   │   ├── audio/                   # TTS audio guide
│   │   └── widgets/                 # Reusable UI components
│   └── storage/
│       └── session_store.dart       # Hive boxes for state
├── android/app/src/main/cpp/
│   ├── vulkan_engine.h/cpp          # Vulkan compute shaders
│   ├── native_image.h/cpp           # OpenCV image wrapper
│   ├── tensor_staging.h/cpp         # AI input buffers
│   ├── texture_bridge_jni.cpp       # JNI texture bridge
│   └── shaders/spv/*.h              # Precompiled SPIR-V
├── assets/models/
│   ├── u2netp.onnx                  # Background removal
│   ├── u2net_human_seg.onnx         # Human segmentation
│   ├── yunet_int8.onnx              # Face detection
│   └── face_landmarker.task         # MediaPipe face mesh
├── doc/
│   ├── WORKFLOW_PLAN.md             # Feature specifications
│   └── ...
├── architecture.md                  # Zero-copy architecture docs
├── tensor_staging_architecture.md   # Staging buffer implementation
├── UI_DESIGN_SPEC.md                # Complete UI specification
└── pubspec.yaml                     # Dependencies
```

---

## Key Implementation Patterns

### 1. Handle-Based Resource Management
All native resources (images, engines, textures) use integer handles instead of direct pointers in Dart, preventing memory safety issues.

### 2. Triple-Fallback Processing
Operations try multiple execution paths:
1. Vulkan GPU (fastest)
2. Native OpenCV via NativeImg (zero-copy)
3. dartcv4 CPU (fallback)

### 3. Lazy Initialization
Heavy resources (ONNX models, Vulkan context) load on first use, not app startup.

### 4. Stream-Based Frame Processing
Camera frames flow through streams with throttling:
```dart
_engine.frameStream?.listen((frame) {
  final guidance = _guidanceChecker.check(...);
  setState(() => _lastGuidance = guidance);
});
```

### 5. CustomPaint Overlays
Camera guidance rendered via CustomPainter to avoid widget tree overhead:
```dart
CustomPaint(
  painter: _GuidanceOverlayPainter(guidance, face, body),
)
```

---

## Performance Optimizations

1. **No shadows on camera screens** (causes GPU overdraw)
2. **Opacity instead of AnimatedOpacity** in hot paths
3. **RepaintBoundary disabled** on camera preview
4. **Pre-allocated staging buffers** reused across frames
5. **FP16 precision** for AI models (faster, less memory)
6. **Hardware interpolation** for mask upscaling
7. **Debounce config changes** (200ms) in template screen

---

## Outstanding Work Items (from documentation)

1. **Clothing Overlay Feature**: Virtual try-on via diffusion inpainting or texture warp
2. **Full Pipeline Integration**: Combine all edit steps into single automated flow
3. **Model Training Guidelines**: Document exists but needs implementation
4. **Additional Shader Kernels**: Expand Vulkan compute library

---

## Conclusion

Fautomatik represents a sophisticated approach to mobile photo editing, prioritizing zero-copy data flows and hardware acceleration at every layer. The architecture successfully bridges Flutter's UI capabilities with native C++ performance, enabling real-time AI processing on mid-range Android devices. The codebase demonstrates strong separation of concerns between UI, business logic, and native compute layers, with clear patterns for extending functionality.
