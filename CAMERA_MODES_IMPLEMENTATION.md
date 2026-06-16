# Camera Modes Implementation Summary

## Overview
Consolidated three separate camera screens (Photo Booth, Standard Camera, Scanner) into a single unified camera screen with toggleable modes.

## Changes Made

### 1. New File: `/lib/features/camera/unified_camera_screen.dart`
Created a comprehensive unified camera screen with the following features:

#### Three Camera Modes
- **Standard Mode** (default): Full manual control, tap-to-focus, no auto features
- **Face/ID Mode**: ID verification style with face+shoulder detection, auto-capture option
- **Scanner Mode**: Document scanning with edge detection and auto-capture

#### UI Layout
- **Left Collapsible Panel**: Mode selector with 3 toggle buttons (Face/ID, Standard, Scanner)
- **Right Collapsible Panel** (Standard mode only): Manual controls (zoom, exposure, flash)
- **Bottom Bar**: Context-aware action buttons based on selected mode
- **Top Bar**: Mode title and back button

#### Face/ID Mode Features
- **L-shaped corner frames**: Position adjustable (20%-80% via slider), preference saved
- **Oval face guide**: Centered, zoomable from 20%-80% of screen width
- **Vertical zoom slider**: Right side control for oval size adjustment
- **Auto-capture toggle**: On/off with visual countdown indicator
- **Full/Crop capture toggle**: Choose between full frame or cropped to guide
- **MediaPipe face detection**: Real-time face mesh tracking
- **Body pose detection**: Full body framing guidance
- **Audio guidance**: Voice instructions for positioning

#### Scanner Mode Features
- **Edge detection overlay**: Green highlight when document detected
- **Auto-capture toggle**: Automatic capture when stable edges found
- **Flash control**: Torch toggle for low-light scanning
- **Grid overlay**: Rule-of-thirds guide

#### Standard Mode Features
- **Full view**: No overlays, clean preview
- **Tap-to-focus**: Touch anywhere to set focus point
- **Manual controls**: Zoom (1x-5x), exposure (-2 to +2), flash
- **DSLR-style experience**: User has full freedom with reasonable defaults

#### Performance Optimizations
- **Throttled processing**: 150ms throttle for Face/ID mode, 100ms for Scanner
- **Efficient downscaling**: Preview frames downscaled before processing
- **Minimal overlay painting**: Only essential graphics rendered
- **Stream management**: Proper cleanup on mode switches

#### Preferences Storage
Using `shared_preferences` to persist:
- Face oval scale (default 40%)
- Corner frame ratio (default 40%)
- Capture full frame setting
- Auto-capture enabled state

### 2. Updated `/lib/features/home/home_screen.dart`
- Replaced three separate camera mode cards with single "Camera" card
- Added import for `UnifiedCameraScreen`
- Simplified home screen navigation

### 3. Updated `/pubspec.yaml`
- Added `shared_preferences: ^2.3.3` dependency for preferences storage

## Key Technical Details

### Face/ID Overlay Painter
- Draws L-shaped corner frames at configurable positions
- Renders oval guide scaled by user preference
- Shows face mesh landmarks when detected
- Displays tilt indicator for head alignment
- Auto-capture progress ring at top

### Scanner Overlay Painter
- Rule-of-thirds grid lines
- Detected edge highlighting in green
- Corner point markers

### Mode Switching
- Smooth transitions with proper stream cleanup
- Camera lens automatically switches (front for Face/ID, back for others)
- State reset on mode change

### Zero-Lag Design
- Frame throttling prevents overload
- Efficient canvas operations
- Minimal setState calls
- Isolate-based image processing where applicable

## Usage

### Accessing Camera
From home screen, tap the "Camera" card to open unified camera. Default mode is Standard.

### Switching Modes
1. Tap camera icon on left edge to expand panel
2. Select desired mode (Face/ID, Standard, or Scanner)
3. Panel auto-collapses after selection

### Face/ID Mode Controls
- **Left bottom button**: Toggle auto-capture
- **Right bottom button**: Toggle Full/Crop capture mode
- **Right side vertical slider**: Adjust oval guide size (20%-80%)
- **Corner frames**: Position remembered per user preference

### Standard Mode Controls
- **Tap on preview**: Set focus point
- **Left bottom button**: Switch camera (front/back)
- **Right bottom button**: Open/close settings panel
- **Right panel**: Zoom slider, Exposure slider, Flash toggle

### Scanner Mode Controls
- **Left bottom button**: Flash/torch toggle
- **Right bottom button**: Toggle auto-capture

## Testing Recommendations

1. **Face Detection**: Test in various lighting conditions
2. **Auto-capture**: Verify stable detection triggers capture
3. **Zoom Slider**: Ensure smooth oval resizing
4. **Preferences**: Confirm settings persist across app restarts
5. **Mode Switching**: Check for memory leaks or crashes
6. **Scanner Edge Detection**: Test with various document sizes and angles

## Future Enhancements

- Add pinch-to-zoom gesture for oval guide
- Implement actual tap-to-focus using CameraController.setFocusPointAndExposurePoint
- Add haptic feedback on auto-capture countdown
- Support multiple face detection for group photos
- Add document type presets for scanner mode
