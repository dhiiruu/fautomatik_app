# Fautomatik App — Session Summary (May 29, 2026)

## Project
Flutter photo-booth app: capture → face/body guidance → edit → template → PDF/print on 4GB Android.

## Device
- Redmi Note M2101K6P (Android 12, ~4GB RAM)
- Device ID: `ac8010ae`
- Test command: `flutter test integration_test/pipeline_integration_test.dart -d ac8010ae`

## Architecture

### Background Removal
- `OnnxBgRemover` — configurable model enum (u2netp / isnetGeneralUse / birefnetGeneralLite)
- `IsolateBgRemover` — isolate inference with `RootIsolateToken`, auto-fallback, 120s timeout, permanent fallback after failure
- Default bg model: isnetGeneralUse (178MB) with u2netp (4.5MB) fallback
- BiRefNet (224MB) OOMs on this device — native ONNX heap >600MB regardless of isolate boundaries

### Camera Engine (`lib/services/camera_engine.dart`)
- Wraps `CameraController` from `camera` package
- YUV→RGBA conversion in isolate `compute`
- Downscaled face detection stream (320px wide)
- High-res `takePicture()` via `takePicture()`
- Selfie-mirror awareness
- Raw NV21 callback for body pose detection (separate from RGBA conversion)

### Face Detection (`lib/pipeline/face/face_pipeline.dart`)
- MediaPipe via `face_detection_tflite` package
- `detectFacesFromMatBytes(Uint8List, width, height, matType: 16)` — expects BGR bytes
- Returns 468 face landmarks + blendshapes

### Body Pose Detection (`lib/pipeline/camera/body_pipeline.dart` + `pose_checker.dart`)
- `google_mlkit_pose_detection` — processes NV21 bytes via `InputImage.fromBytes()` with `InputImageFormat.nv21`
- `BodyData` with 33 landmarks (from `PoseLandmarkType` enum)
- `PoseChecker` — validates full body visible, centered, upright, arms down

### Guidance Checker (`lib/pipeline/camera/guidance_checker.dart`)
- Face position, head tilt (EAR), mouth openness, brightness, backlight, shadow detection
- Runs on downscaled RGBA preview frames

### Photo Editor (`lib/pipeline/compositor/editor.dart`)
- 10 chainable steps: straighten, auto-crop, resize, bg replacement, auto-levels, sharpen, skin smooth, red-eye, border, format/compress
- `OutputConfig.dpi` — patches JPEG JFIF header and PNG pHYs chunk for exact DPI metadata
- Single `edit(config)` call

### Scan Pipeline (`lib/pipeline/camera/scan_pipeline.dart`)
- Edge detection (Sobel), perspective warp (4-point bilinear), auto-crop, auto-levels
- `EdgeDetector` + `PerspectiveWarp` in `lib/pipeline/camera/`
- Stability tracking for auto-capture

### Template Engine (`lib/pipeline/template/template_engine.dart`)
- Configurable paper size, photo size, DPI, spacing, margins, crop marks
- Multi-page grid layout, 3mm min-margin clamp

### PDF Exporter (`lib/pipeline/template/pdf_exporter.dart`)
- Template PNG pages → multi-page PDF via low-level `PdfDocument` API (printing package)

### Audio Guide (`lib/services/audio_guide.dart`)
- `flutter_tts`-based instruction speech for guided mode

## Screens

| Screen | File | Purpose |
|--------|------|---------|
| Home | `lib/screens/home_screen.dart` | Animated gradient menu with 3 mode cards |
| Guided Camera | `lib/screens/guided_camera_screen.dart` | Face mesh + body skeleton overlay, guidance chips, auto-capture, audio |
| Camera | `lib/screens/photo_camera_screen.dart` | Standard point-and-shoot, gallery thumbnail |
| Scan Camera | `lib/screens/scan_camera_screen.dart` | Grid overlay, edge detection, auto-capture, post-warp + enhance |
| Template/Print | `lib/screens/template_print_screen.dart` | PageView preview, paper/photo/DPI/spacing/margin/crop marks config, Save PDF + Print |
| Photo Preview Sheet | `lib/screens/photo_preview_sheet.dart` | Shared draggable bottom sheet for post-capture |

## Theme (`lib/theme/app_theme.dart`)
- Dark theme: background #0D0D0D, surface #1A1A2E, primary #7C4DFF
- `AppTheme.backgroundGradient` — LinearGradient from #0D0D0D to #1A1A2E
- `AppTheme.surfaceDark` — #14142A

## Widgets (`lib/widgets/app_widgets.dart`)
- `GradientButton` — glossy filled/outlined button, now supports optional `child` param
- `IndicatorChip` — small pill for guidance status (green check / red close)
- `CountdownPill` — auto-capture progress indicator
- `PageDots` — page indicator dots

## State
- Unlock via `unlock_notifier.dart` and Riverpod (`state/providers.dart`)
- `FautomatikApp` → `AppShell` (checks unlock) → `_UnlockScreen` or `HomeScreen`

## Current Status
- **31 integration tests pass** on device (~3m)
- **Analyzer**: 0 errors, 0 warnings (13 info-level style hints)
- **Known bug**: GuidedCameraScreen crashes on launch — `_buildPreview()` null check on `_engine.controller!.value.aspectRatio` (partially fixed, needs verification)

## What Was Done This Session
1. Created `photo_preview_sheet.dart` — draggable bottom sheet with retake/layout buttons
2. Rewrote `guided_camera_screen.dart` with new dark/glossy design
3. Rewrote `photo_camera_screen.dart` with new dark/glossy design
4. Rewrote `scan_camera_screen.dart` with new dark/glossy design
5. Rewrote `template_print_screen.dart` with new dark/glossy design
6. Added `AppTheme.backgroundGradient` and `AppTheme.surfaceDark`
7. Added optional `child` parameter to `GradientButton`
8. Removed unused imports across files
9. Fixed analyzer errors (0 errors, 0 warnings now)
10. All 31 tests still pass
11. App crashed on device test (GuidedCameraScreen null check) — fixed the `_buildPreview()` method but device disconnected before verification

## Key Technical Details
- `flutter_onnxruntime` native allocations on native heap; isolate boundaries do not reduce memory
- `RootIsolateToken` + `BackgroundIsolateBinaryMessenger.ensureInitialized` required for MethodChannel in spawned isolates (Flutter 3.41.4)
- `img.copyResize(maintainAspect: true, backgroundColor: ...)` fills empty space with background color
- JPEG DPI cannot be set via `encodeJpg()` in image 4.8.0 — must patch JFIF header bytes post-encode
- Face mesh data captured during preview is reusable for auto-crop/straighten — skip re-detection on high-res capture
- `flutter_tts` used for audio guide instructions in guided camera mode
