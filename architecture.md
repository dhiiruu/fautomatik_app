
# High-Performance Flutter/Native AI Photo Editor Architecture

## 1. The Core Problem: The Dart "Copy Tax"
Traditional Flutter architecture passes image data across platform channels using `Uint8List` or `MethodChannels`. This serializes and deep-copies large image arrays (e.g., a 12MP image requires ~48MB of uncompressed RAM). 

This approach triggers immediate bottlenecks:
* **Dart Garbage Collection (GC) Spikes:** Constant heap allocation and deallocation trigger GC collection routines that freeze the Flutter main UI thread.
* **CPU Bottlenecks:** Forcing the CPU to copy large arrays back and forth delays execution to the hardware layer.

---

## 2. The Zero-Copy Solution: Shared Native Pointers
Instead of moving pixels between Dart, C++, and hardware targets, the image data remains absolute in a single physical RAM block. The system passes a 64-bit integer—the **memory pointer address**—between execution environments.

### Data Lifecycle Matrix

```

[ Raw File on Storage ]
│
▼ (Decoded exactly once via native worker thread)
[ C++ Allocation / AHardwareBuffer ] ◄── Pointer (e.g., 0x7FFF)
│
├──► [ Dart FFI Pointer ] ──► Bound to Flutter Texture Widget (Display)
│
├──► [ OpenCV Engine ] ────► In-place Matrix Calculations (Sliders)
│
└──► [ ONNX Mobile ] ──────► Sub-Tensor Preprocessing (AI Models)

```

1. **Native Allocation:** The raw image file decodes inside native memory via a C++ worker thread into an `AHardwareBuffer` or an unmanaged heap array (`0x7FFF`).
2. **Dart Interface:** Dart uses `dart:ffi` to hold an immutable reference to `0x7FFF`. The Dart VM manages a light 64-bit reference address instead of a heavy raw pixel allocation.
3. **UI Pipeline:** The native layer registers the pointer location directly into the Flutter engine's **`TextureRegistry`**. The UI displays the frame via a `Texture(textureId: ...)` widget. This passes raw GPU surface handles directly to the Impeller graphics backend, bypassing Dart completely.

---

## 3. Resolving Multi-Model Sub-Tensor Ingestion
AI models require strict, differing tensor dimensions (e.g., MobileSAM at $1024 \times 1024$, U2Net at $320 \times 320$, Real-ESRGAN at $256 \times 256$). 

The pipeline does not alter or reshape the primary high-resolution buffer (`0x7FFF`). Instead, it uses a **Dual-Track Input Architecture**:

* **Track A (The Master State Buffer):** Stays at original camera resolution. Traditional filter adjustments (contrast, brightness, exposure) alter the pixels directly at this address.
* **Track B (Dynamic Sub-Tensor Generation):** When an AI task triggers, the native engine reads from `0x7FFF`, downsamples a quick, volatile copy using hardware-accelerated linear interpolation directly inside native RAM, and routes it directly to the model's processing slot.

### Model Sizing Routing
* **MobileSAM Workflow:** C++ wraps `0x7FFF` ➔ Scales volatile copy to $1024 \times 1024$ ➔ Executes via GPU/NPU ➔ Spits out mask ➔ High-res upscaler maps mask contours back onto the master buffer.
* **U2Net Workflow:** C++ wraps `0x7FFF` ➔ Scales volatile copy to $320 \times 320$ ➔ Pulls fast transparency matte.

---

## 4. Hardware Allocation Protocol (Android)

To minimize execution overhead and prevent thermal throttling during bulk image processing, operations map directly to specific hardware execution blocks:

| Operation Class | Target Hardware Slot | Execution Mechanism |
| :--- | :--- | :--- |
| **Landmark Trackers**<br>(MediaPipe, YOLO-Face) | **NPU** (Neural Processing Unit) | Handled via Android NNAPI or Qualcomm QNN execution providers inside ONNX Runtime Mobile. |
| **Generative & Extraction Models**<br>(RMBG, MobileSAM, U2Net) | **GPU Cores** (Vulkan / OpenGLES) | Deployed using **FP16 precision** configuration to prevent color quantization artifacts while accelerating vector math. |
| **Traditional Spatial Enhancements**<br>(Filters, Blending, Contrast) | **GPU Fragment Shaders** | Executed directly on the underlying texture layers using parallel GLSL/MSL shader programs. |
| **Pre-processing / Metadata Operations**<br>(Rotations, Normalization, Exif) | **CPU Thread Pool** | Multi-threaded native C++ routines using optimized OpenCV structures. |

```