# Fautomatik — UI Design Spec

## Overview
Photo-booth & print-scan app. 3 camera modes → edit → template layout → PDF/print. Target: 4GB Android phone (Redmi Note 10, Android 12). Must be **ultra fast, slick, classy**. Dark theme, minimal chrome, gesture-driven, haptic feedback.

## Visual Style
- **Theme**: Dark with deep purple/indigo primary accent. Background: near-black (#0D0D0D). Cards: #1A1A2E with subtle border (#2A2A4E).
- **Typography**: Sans-serif, light weight (300/400), generous letter-spacing for headers. Monospace for counts/dimensions (e.g. "4×6″", "300 DPI").
- **Motion**: 300ms ease-in-out. Page transitions: slide-up from bottom. Overlays: fade + slight scale. Micro-interactions: subtle spring on button press.
- **Sound**: Short haptic taps on interaction (HapticFeedback.lightImpact). No gratuitous sounds.
- **Status bar**: Transparent, light icons.

## Screen Flow
```
Menu → Guided Camera / Camera / Scan Camera → Photo Preview → Template/Print → Save/Print
```

## Screen 1: Menu (`main.dart` -> `_CameraMenuScreen`)
- Full-bleed dark background with subtle animated gradient or particle effect (subtle — don't distract).
- Central logo: stylized "F" mark (icon: `Icons.filter_hdr` or custom SVG) with "Fautomatik" wordmark.
- 3 cards stacked vertically, each with:
  - **Icon** on left in colored container (rounded 12px).
  - **Title** (bold, white) + **subtitle** (grey, smaller).
  - **Chevron** on right.
  - Press: spring scale down effect, then page transition.
- Cards:
  1. **Photo Booth** — `Icons.face_retouching_natural`, deep purple. "Guided selfie with face & body detection"
  2. **Camera** — `Icons.camera_alt`, teal. "Standard point-and-shoot"
  3. **Scan Photo** — `Icons.document_scanner`, amber. "Scan printed photos with auto-crop"
- Bottom: green pill showing unlock timer "Unlocked: 01:23 remaining". Tapping it is not needed (just a status indicator).
- Unlock screen (when locked): centered lock icon, app name, "Watch a rewarded ad to unlock", big CTA button. Simple, no clutter.

## Screen 2: Guided Camera (`guided_camera_screen.dart`)

### Layout
- Full-screen camera preview (edge-to-edge, no app bar).
- Top edge: translucent gradient strip with:
  - Back button (white, subtle shadow)
  - Auto-capture indicator pill (orange/green "Auto" with frame counter)
  - Throbber when capturing
- Bottom edge: semi-transparent gradient bar with 3 controls:
  - **Flip camera** button (left)
  - **Capture button** (center) — large white circle (72px) with thin white border (4px), inner translucent fill. When pressed: `HapticFeedback.heavyImpact`, animate ring pulse outward. When capturing: show CircularProgressIndicator overlay.
  - **Auto-capture toggle** (right) — timer icon, orange when off, green pulse when on and detecting stable subject.
- **Guidance panel**: floating above bottom bar, centered horizontally:
  - Main instruction chip: translucent black pill with white text. Updates smoothly (cross-fade) as guidance state changes.
  - Below it: row of mini indicator chips (8-12px tall, rounded pill). Green check / red X icon + 1-2 word label. Wrap to next line if needed. Each chip animates in/out with slight scale when state changes.
  - Chips: Face, Center, Size, Level, Eyes, Expression, Light, Backlit, Body, Full, Upright, Arms
  - Green chips fade slightly to background when OK, red chips are more prominent when failing.
- **Audio guidance**: small speaker icon top-right (above instruction panel) that pulses briefly when TTS speaks. Toggle mute on tap.

### Overlay (CustomPaint)
- **Face guide oval**: thin white/green dashed ellipse at center. Width ~25% of frame. Breathing animation (subtle scale pulse ±3% when face not detected).
- **Face mesh**: cyan semi-transparent lines (contour, eyes, lips). Only when face detected. Fade in smoothly.
- **Eye line**: yellow line connecting eyes, changes to green when level, red when tilted.
- **Body skeleton**: lime-green stick figure (12 bones: shoulders, elbows, wrists, hips, knees, ankles + joint dots). Only when body detected. Fade in/out.
- **Auto-capture ring**: green translucent circle that grows from center outward as stability increases. Max size at capture trigger. Smooth continuous animation.
- **Direction arrow**: if face/body is off-center, a subtle orange chevron pointing toward where the subject should move. Fades in/out.

## Screen 3: Standard Camera (`photo_camera_screen.dart`)
- Full-screen camera preview. No overlays (no face/body detection).
- Clean, minimal. Like iOS/macOS Camera app.
- Bottom bar: gallery thumbnail (left, rounded 8px border), capture button (center, same style), flip camera (right).
- Tapping gallery thumbnail: shows captured photo in a bottom sheet (draggable, half height) with "Layout & Print" button.
- No shutter sound (or use phone's default camera sound).

## Screen 4: Scan Camera (`scan_camera_screen.dart`)
- Full-screen camera preview (back camera only).
- **Grid overlay**: subtle white 3x3 grid (rule of thirds lines, 30% opacity).
- **Photo boundary**: green neon-like border highlighting detected photo edges. Corner dots in yellow. Smooth animate as boundary updates. When stable, border becomes solid green and glows slightly.
- **Status text**: floating chip at top showing "Center a printed photo" (white) or "Photo detected — 85%" (green).
- **Torch toggle**: flash icon bottom-left, yellow when on.
- **Auto-capture**: no explicit toggle — it auto-captures when stable. Show a brief "Hold..." indicator.
- After capture: full-screen preview of corrected photo with "Scan Again" (outline button) and "Layout & Print" (filled button).

## Screen 5: Photo Preview (transition between capture and template)
- After capture in any mode, briefly show the photo full-screen with a subtle "Developing..." animation (shimmer overlay, ~1s).
- Then slide up a bottom sheet with:
  - Thumbnail of captured photo
  - "Edit" button (runs PhotoEditor with smart defaults)
  - "Layout & Print" button (goes to template screen)
  - "Retake" button (goes back to camera)
- This screen is temporary — ideally merge it into the camera screens (gallery preview) and template screen. Keep it minimalist.

## Screen 6: Template/Print (`template_print_screen.dart`)

### Layout
- White/light background (this is a "work" screen, not camera).
- App bar: "Print Layout" title, no back button (use system back).
- **Main area**: PageView of template pages. Each page shown as a card with subtle shadow. Swipe left/right to browse pages. Page dots indicator below (if >1 page).
- **Bottom panel**: collapsible "Settings" section (expandable/collapsible with animation):
  - **Paper**: dropdown (4×6, 5×7, 6×8, A4, A5) — compact, dense.
  - **Photo size**: dropdown (wallet through 5×7).
  - **DPI**: dropdown (72, 150, 200, 300, 600, 1200). Show " (recommended)" badge on 300.
  - **Spacing**: slider 0-10mm, show value in mm.
  - **Margin**: slider 3-20mm, show value in mm.
  - **Crop marks**: toggle switch.
  - All controls update preview in real-time (debounced 200ms).
- **Action bar**: sticky at bottom:
  - "Save PDF" (outline button, left)
  - "Print" (filled button, right — deep purple)
  - Show estimated photo count and page count between them.

### Interaction
- Changing paper/photo size recalculates layout. Show brief "x photos per page" toast.
- Preview updates with a subtle cross-fade (not a hard cut).
- Print button: show loading overlay with "Generating PDF..." and a progress indicator (determinate if possible).
- On success: brief success haptic + snackbar, then system print dialog appears.

## Responsive / Adaptive
- Portrait only (lock orientation).
- All hit targets ≥48px.
- No horizontal overflow — use scrollable config panel.
- Camera preview aspect ratio should fill the screen (center crop).

## Performance Notes
- No shadows on camera screens (they cause GPU overdraw on sub-60fps devices).
- Use `Opacity` instead of `AnimatedOpacity` in the hot path (frame stream).
- Preload fonts, avoid network fonts.
- Keep overlay paints minimal (repaint only when state changes, not every frame).
- Disable `RepaintBoundary` on camera preview widget.

## Animation Recipes
- **Card tap**: `Transform.scale(0.96)` on tap down, spring back on up. 150ms.
- **Page transition**: `SlideTransition` from bottom (Offset(0, 0.1) to Offset.zero) + fade. 300ms ease-out.
- **Guidance chip change**: `AnimatedScale` + `AnimatedOpacity` on each chip. 200ms.
- **Capture button press**: radial ripple from center + scale to 0.9 on press. 100ms.
- **Auto-capture progress ring**: `AnimatedContainer` with circular progress, linear.
- **Overlay fade**: cross-fade between face mesh on/off states. 200ms.
- **Template preview update**: short cross-fade (150ms) when config changes.
- **Snackbar**: slide up from bottom, auto-dismiss after 2s.

## Color Palette
```
Background:       #0D0D0D
Surface:          #1A1A2E
Surface border:   #2A2A4E
Primary:          #7C4DFF (deep purple accent)
Primary light:    #B388FF
Secondary:        #00BFA5 (teal)
Accent (scan):    #FFAB00 (amber)
Success:          #00E676
Error:            #FF5252
Warning:          #FFD740
Text primary:     #FFFFFF
Text secondary:   #9E9E9E
Overlay text:     #FFFFFF (on average-dark backgrounds)
```

## Assets Needed
- Custom SVG logo ("F" mark) — or use `Icons.auto_awesome` as fallback.
- App icon (rounded square, gradient background, white "F").
- Splash screen (dark background, centered logo, 1.5s fade-out).
- Notification icon for background processing.
- Audio instruction clips (optional — can use TTS as fallback).

## Deliverable Format
Generate complete Flutter widget files:
- `lib/screens/home_screen.dart` (menu)
- `lib/screens/guided_camera_screen.dart` (replace existing — keep all engine calls intact, only change UI wrapping)
- `lib/screens/photo_camera_screen.dart` (replace existing)
- `lib/screens/scan_camera_screen.dart` (replace existing)
- `lib/screens/template_print_screen.dart` (replace existing)
- `lib/screens/photo_preview_sheet.dart` (new — cross-camera post-capture sheet)
- `lib/theme/app_theme.dart` (new — ThemeData + extensions)
- `lib/widgets/` reusable components (gradient button, indicator chip, countdown pill, etc.)

**Important**: Do not change any engine files (`lib/pipeline/*`, `lib/services/*`). Only touch `lib/screens/*`, `lib/theme/*`, `lib/widgets/*`, and `lib/main.dart` (only to add theme).

## Engine API Reference (for UI devs to call)

```dart
// Camera modes are separate screens — no shared camera engine needed across screens.
// Each screen creates its own CameraEngine internally.

// Guided camera flow:
final engine = CameraEngine();
await engine.init(lens: CameraLens.front);
await engine.startFrameStream(onFaceDetect: ..., onRawFrame: ...);
engine.frameStream.listen((frame) { ... update guidance state ... });
final photo = await engine.takePhoto();

// Photo editing:
final editor = PhotoEditor();
final edited = editor.edit(
  sourceBytes: jpegBytes,
  sourceWidth: w,
  sourceHeight: h,
  faceData: face, // optional
  config: EditConfig(
    straighten: StraightenConfig(),
    resize: ResizeConfig(width: 1200),
    lighting: LightingConfig(),
    sharpen: SharpenConfig(),
    output: OutputConfig(format: 'jpg', quality: 92, dpi: 300),
  ),
);

// Template + print:
final engine = TemplateEngine();
final result = engine.place(photos: [editedBytes], config: templateConfig);
// result.pages = list of PNG bytes, one per page

final exporter = PdfExporter();
final pdfBytes = await exporter.export(templateResult: result, config: config);

// Print or save:
await Printing.layoutPdf(onLayout: (format) => pdfBytes);
await Printing.sharePdf(bytes: pdfBytes, filename: 'photos.pdf');
```

## File Structure (UI only)
```
lib/
  main.dart                    // add ThemeData, keep ProviderScope
  theme/
    app_theme.dart             // ThemeData, dark theme, color scheme, text theme
  widgets/
    gradient_button.dart       // re-usable filled/outline buttons
    indicator_chip.dart        // guidance chip with check/X
    countdown_pill.dart        // unlock timer or auto-capture counter pill
    page_dots.dart             // page indicator dots
    camera_preview_wrapper.dart // handles aspect ratio, clip
  screens/
    home_screen.dart           // menu with 3 cards
    guided_camera_screen.dart  // photo booth — face+body overlay
    photo_camera_screen.dart   // standard camera — clean minimal
    scan_camera_screen.dart    // scan — grid + edge overlay
    photo_preview_sheet.dart   // bottom sheet after capture
    template_print_screen.dart // layout preview + config + print
```
