# Model Reference

## Background Removal (ONNX)

All outputs are a single-channel mask `[1, 1, H, W]` — same spatial size as input.
Values are logits (before sigmoid), range varies by model.

| Model | File | Input Shape | Output Shape | Size | Quality | Speed |
|-------|------|-------------|--------------|------|---------|-------|
| U2NetP | `u2netp.onnx` | `[1, 3, 320, 320]` | `[1, 1, 320, 320]` | 4.4 MB | Medium | Fast |
| MODNet | `models/modnet.onnx` | `[1, 3, H, W]` (dynamic) | `[1, 1, H, W]` | 25 MB | High (matting) | Fast |

### Usage
- Resize/crop input image to model's expected input size before inference.
- Apply sigmoid on output mask: `mask = 1 / (1 + exp(-logits))`.
- Resize mask back to original image size for compositing.
- All models: type=1 (FLOAT32), channels = NCHW.

## Face Detection (ONNX)

| Model | File | Input Shape | Output Shape | Size |
|-------|------|-------------|--------------|------|
| YuNet INT8 | `yunet_int8.onnx` | `[1, 3, 640, 640]` | see below | 0.12 MB |

### YuNet Outputs (3-scale FPN)

| Output Name | Shape | Description |
|-------------|-------|-------------|
| `cls_8` | `[1, 6400, 1]` | Classification scores (stride 8) |
| `cls_16` | `[1, 1600, 1]` | Classification scores (stride 16) |
| `cls_32` | `[1, 400, 1]` | Classification scores (stride 32) |
| `obj_8` | `[1, 6400, 1]` | Objectness scores (stride 8) |
| `obj_16` | `[1, 1600, 1]` | Objectness scores (stride 16) |
| `obj_32` | `[1, 400, 1]` | Objectness scores (stride 32) |
| `bbox_8` | `[1, 6400, 4]` | Bounding boxes (stride 8) |
| `bbox_16` | `[1, 1600, 4]` | Bounding boxes (stride 16) |
| `bbox_32` | `[1, 400, 4]` | Bounding boxes (stride 32) |
| `kps_8` | `[1, 6400, 10]` | 5 keypoints × 2 coords (stride 8) |
| `kps_16` | `[1, 1600, 10]` | 5 keypoints × 2 coords (stride 16) |
| `kps_32` | `[1, 400, 10]` | 5 keypoints × 2 coords (stride 32) |

Type=1 (FLOAT32), channels=NCHW.

## MediaPipe Face Mesh (TFLite, task bundle)

File: `face_landmarker.task`
Format: zip bundle containing 4 files.

### face_detector.tflite (BlazeFace short-range, 224 KB)

| | Shape | Description |
|---|-------|-------------|
| Input | `[1, 128, 128, 3]` FLOAT32 | RGB image (NHWC) |
| Output 1 | anchors | Bounding box regression |
| Output 2 | scores | Face detection scores |

### face_landmarks_detector.tflite (FaceMesh V2, 2.5 MB)

| | Shape | Description |
|---|-------|-------------|
| Input | `[1, 256, 256, 3]` FLOAT32 | Cropped face (NHWC) |
| Output 1 | `[1, 478, 3]` FLOAT32 | 478 face landmarks (x, y, z) |

### face_blendshapes.tflite (933 KB)

| | Shape | Description |
|---|-------|-------------|
| Input | `[1, 146, 2]` FLOAT32 | Face mesh features |
| Output 1 | `[1, 52]` FLOAT32 | 52 blendshape coefficients |

### geometry_pipeline_metadata_landmarks.binarypb (19 KB)
Protocol buffer with face model topology (triangulation indices).
