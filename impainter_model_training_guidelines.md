# Strategic Instructions: Training a <15MB Mobile-First Inpainter/Outpainter

This document outlines the step-by-step non-code instructions required to successfully train a highly compressed, production-grade image inpainting and outpainting model using Teacher-Student Knowledge Distillation. 

The strategy is intentionally optimized to deliver industry-standard visual fidelity within a strict **15 MB hardware footprint**, preventing thermal throttling and Out-Of-Memory (OOM) crashes on standard mobile devices.

---

## Phase 1: Data Pipeline Architecture & Dual-Masking Strategy

To make a tiny model capable of both filling internal holes (object removal) and expanding external boundaries (outpainting) without splitting it into two separate networks, your data pipeline must train the model symmetrically.

1. **Resolution Baseline:** Set your data loader to resize all training imagery to a consistent baseline (e.g., $256 \times 256$ pixels). This keeps memory predictable during training.
2. **The 4-Channel Input Packing:** * Do not pass the masked image and the mask array as separate inputs. 
   * Force your data loader to concatenate the masked RGB image ($3\text{ channels}$) and the binary mask ($1\text{ channel}$) along the channel dimension into a single $4\text{-channel}$ tensor. This drastically optimizes early-layer caching on mobile GPUs.
3. **Dynamic Mask Switching (50/50 Probability):** For every batch step, flip a coin to determine the mask type:
   * **Inpainting Mode (50%):** Generate random, irregular stroke masks using random lines and varying thicknesses to simulate scratches, blemishes, and object erasures.
   * **Outpainting Mode (50%):** Generate peripheral border masks by randomly shaving off a percentage (10% to 25%) of the outer top, bottom, left, or right margins. This forces the model to synthesize content purely from the interior outward.

---

## Phase 2: Structural Constraints & Student Architecture

To stay under 15 MB, you are limited to roughly **3.5 Million to 3.7 Million parameters** (assuming standard Float32 weights). Transformers and dense multi-step diffusion blocks are mathematically disqualified.

1. **The Core Backbone:** Use a highly stripped-down Encoder-Decoder structure with a narrow bottleneck (e.g., maximum 128 channels). Restrict your bottleneck to only 3 or 4 residual blocks.
2. **Integrating Fast Fourier Convolutions (FFCs):** * Traditional convolutions scale poorly because their receptive field expands linearly with depth. A small model cannot "see" across the whole image to find textures for outpainting.
   * Replace the standard convolutions inside your bottleneck residual blocks with **FFC layers**. 
   * Inside each FFC layer, split the incoming channels: allocate **70% of the channels to a Local Path** (standard $3 \times 3$ convolutions for edges/local detail) and **30% to a Global Path** (which computes a 2D Real Fast Fourier Transform).
   * Applying convolutions in the frequency domain gives the network an immediate, image-wide global receptive field from the very first block, allowing it to accurately project structural lines across the canvas.

---

## Phase 3: The Teacher-Student Distillation Mechanics

Your teacher model will be a pre-trained **LaMa (Large Mask Inpainting)** model, which natively utilizes heavy FFC backbones. The teacher remains frozen throughout the entire process.

1. **Channel Alignment Projections:** The teacher model likely uses a wide bottleneck (e.g., 256 channels), while your student is restricted to a lean 128 channels. To calculate feature matching, implement a temporary $1 \times 1$ convolution layer that upsamples the student's hidden features to match the teacher's dimensions *only* during the loss calculation step. This layer is discarded after training and won't bloat your mobile file size.
2. **The Loss Composition Engine:** Calculate three distinct losses simultaneously:
   * **Ground-Truth L1 Loss:** Meant to keep the student anchored to the actual sharp reality of the original unmasked image.
   * **Teacher Soft-Target Loss:** An L1 loss calculated directly between the student’s final image prediction and the teacher’s final image prediction. The teacher provides a smoother, optimized manifold that is significantly easier for a tiny network to converge toward than raw ground truth pixels.
   * **Latent Feature Matching Loss:** An Mean Squared Error (MSE) loss calculated between the student’s adapted bottleneck layer and the teacher’s bottleneck layer. This forces the student to "think" like the teacher structurally.

---

## Phase 4: Step-by-Step Training Workflow Execution

To ensure stable convergence without gradient explosions, execute your training schedule in three strict chronological steps:

1. **Step 1: Feature Alignment (Warm-up Phase):**
   * Freeze the teacher. Train the student using *only* the Latent Feature Matching loss and a high-frequency reconstruction loss for the first 10-15 epochs. 
   * Do not introduce competitive adversarial structures yet. This phase ensures the student's internal hidden states match the teacher's geometry before forcing hard pixel synthesis.
2. **Step 2: Joint Generation & Distillation:**
   * Activate all components of the Loss Composition Engine (Ground-Truth, Teacher Soft-Targets, and Latent Features). 
   * Let the student train until its structural outputs match the teacher's macro-geometry across both inpainting and outpainting paradigms.
3. **Step 3: Adversarial Texture Refinement (Fine-Tuning Phase):**
   * Introduce a lightweight, patch-based Discriminator network (like a PatchGAN discriminator) to train alongside the student model.
   * Apply an adversarial hinge loss. This step forces the student to transition away from slightly blurry or soft "average" outputs and begin generating high-frequency textures, sharp details, and clean boundary blending.

---

## Phase 5: Production Export & Mobile Deployment Optimization

Once training is complete, the model must be optimized to guarantee it fits your strict memory requirements on real iOS or Android devices.

1. **Eliminate Training Scaffolding:** Remove the $1 \times 1$ channel adapter and the discriminator network entirely. You only export the bare student encoder-decoder.
2. **Serialized Format Conversion:** Convert your trained PyTorch weights into a portable edge format—specifically **ONNX (Opset 14+)** or a **TFLite flatbuffer**.
3. **Mandatory Post-Training Quantization:** * Run a post-training **FP16 (Float16) quantization** routine during the serialization process. 
   * This operation slashes your binary file size exactly in half (compressing your ~14 MB FP32 model down to a lean **~7 MB** file).
   * FP16 quantization allows modern mobile neural engine chips and mobile GPUs to process the tensors entirely within low-latency cash lines, completely preventing thermal throttling and mid-process OOM execution kills.