# Photo Processing Workflow Plan

## Photo Selection
- User picks photo from gallery **or** uses **Guided Camera**

## Guided Camera
- Camera viewfinder shows a **face oval guide** — subject must align face within the oval
- When subject is **stable for ~600ms**, triggers **auto-capture**
- Captured photo proceeds into the processing pipeline

## Processing Pipeline (in order)
1. **Face/Body detection** (MediaPipe face mesh / body pose)
2. **Remove background** (U²-Net / ISNet / BirefNet)
3. **Add new background** (user-defined solid color)
4. **Crop at user-defined size** (px / mm / inch) — uses face data to frame perfectly
5. **Head tilt / orientation correction**
6. **Brightness & sharpness correction**
7. **Light / shadow correction**
8. **Add border** (yes/no, inner/outer, color, dashed/solid, thickness in px)
9. **Compress** (yes/no, max KB/MB)

## Standalone Feature Buttons
Each feature also available as a **single-button action** (run individually without full pipeline):

| Button | Description |
|--------|-------------|
| **Remove BG** | One-tap background removal |
| **Auto Crop** | Crop to user-defined size using face data |
| **Compress** | Compress to target KB/MB |
| **Straighten** | Auto-detect and correct head tilt / horizon |
| **Auto Lighting** | Auto balance brightness, contrast, shadows |
| **Sharpen** | Smart sharpening |
| **Skin Smooth** | Subtle skin blemish / pore smoothing |
| **Red-Eye Fix** | Auto detect & remove red-eye |
| **BG Color** | Change background to a solid color |
| **Border** | Add border with full controls |
| **Resize** | Scale to specific dimensions |
| **Convert Format** | Change between PNG / JPG / WEBP |
| **Print Template** | Layout photo(s) onto a printable template with auto-arrangement |

## Result Screen
- Shows the final processed photo
- **Action buttons:** Save / Edit / Print Template

### Edit Button
- Opens a **minimalist editing panel** for fine-tuning

### Print Template
- User selects a **standard template size** (common presets) **or inputs custom dimensions**
- User selects photo(s) to place in the template
- User sets **number of copies** per photo
- System **automatically arranges** photos within the template — optimizes orientation and layout to **maximize paper usage** (auto-rotation, tight packing)
- Preview and export the final printable sheet

---

## Clothing Overlay Feature

### Goal
Add/replace clothing on the subject with **realistic output** using the **simplest possible approach**.

### Recommended Approach: Virtual Try-On via Diffusion Inpainting (Best realism / Simpler integration)

1. **Body segmentation** — Use MediaPipe Selfie Segmenter or YOLOv8-pose to get a precise body mask (torso, arms, legs regions)
2. **Clothing prompt** — User selects a clothing type (t-shirt, suit, etc.) and optional color; system generates a text prompt internally (e.g. "a person wearing a blue suit, realistic photo")
3. **On-device diffusion inpainting** — Feed the original photo + body mask + prompt into a lightweight diffusion model (e.g. Stable Diffusion XL-Turbo via ONNX/TFLite) to inpaint clothing only
4. **Blend refinement** — Feather mask edges, match brightness/color between original skin/hair and new clothing region
5. **Result** — Realistic clothing replacement with proper texture, folds, and lighting

### Lighter Fallback: Texture Warp (No AI generation)

1. **Body landmarks** — MediaPipe Pose → torso/keypoints for shoulders, chest, waist
2. **Clothing template** — Pre-rendered clothing image mapped to a standard pose
3. **Thin-plate spline warp** — Warp template to match subject's body landmarks
4. **Alpha blending + color transfer** — Composite over subject, transfer color stats (mean/std) from original to match scene lighting
5. **Result** — Decent for uniform clothing (solid colors, simple patterns), less realistic for complex textures

### Recommended library stack
- `mediapipe` / `google_ml_kit_pose_detection` — pose landmarks & body segmentation
- `tflite` / `onnxruntime` — diffusion model inference
- `image` / `image_processing` — warp, blend, color transfer
