// Advanced Image Processing Shaders (Metal Syntax for iOS/macOS)
// These shaders implement Denoise, Dehaze, and Face Sculpting logic.

#include <metal_stdlib>
using namespace metal;

// --- 1. Bilateral Denoise Shader ---
// Preserves edges while smoothing noise.
// Parameters: sigma_space (radius), sigma_color (sensitivity)

kernel void bilateral_denoise(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant float &sigma_space [[buffer(0)]],
    constant float &sigma_color [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 dim [[texture_dimensions(0)]]) 
{
    float3 center = inTexture.read(gid).rgb;
    float totalWeight = 0.0;
    float3 sumColor = float3(0.0);
    
    int radius = int(sigma_space * 2.0);
    
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            int2 coord = int2(gid.x + x, gid.y + y);
            
            // Boundary check
            if (coord.x < 0 || coord.x >= int(dim.x) || coord.y < 0 || coord.y >= int(dim.y)) continue;
            
            float3 neighbor = inTexture.read(coord).rgb;
            
            // Spatial weight (Gaussian based on distance)
            float distSq = float(x*x + y*y);
            float wSpace = exp(-distSq / (2.0 * sigma_space * sigma_space));
            
            // Range weight (Gaussian based on color difference)
            float colorDiff = length(center - neighbor);
            float wRange = exp(-colorDiff * colorDiff / (2.0 * sigma_color * sigma_color));
            
            float weight = wSpace * wRange;
            
            sumColor += neighbor * weight;
            totalWeight += weight;
        }
    }
    
    outTexture.write(float4(sumColor / totalWeight, 1.0), gid);
}

// --- 2. Dehaze Shader ---
// Uses Dark Channel Prior approximation to remove haze.
// Parameters: haze_amount (0.0 to 1.0), threshold

kernel void dehaze(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant float &haze_amount [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 dim [[texture_dimensions(0)]]) 
{
    float3 color = inTexture.read(gid).rgb;
    
    // Approximate transmission map using local minimum (simplified for single pass)
    // In a real implementation, this requires two passes or a larger sample radius
    float minChannel = min(min(color.r, color.g), color.b);
    
    // Atmospheric light assumption (usually ~1.0 for white haze)
    float atmosphericLight = 1.0;
    
    // Transmission t = 1 - haze_amount * (1 - minChannel)
    // Simplified: We boost contrast based on how "gray" the pixel is
    float transmission = 1.0 - (haze_amount * (1.0 - minChannel));
    
    // Recover radiance: I = (J - A(1-t)) / t  =>  J = (I - A) / t + A
    // Simplified contrast stretch:
    float3 dehazed = (color - atmosphericLight) / max(transmission, 0.1) + atmosphericLight;
    
    // Clamp and mix with original based on strength
    dehazed = clamp(dehazed, 0.0, 1.0);
    float3 result = mix(color, dehazed, haze_amount);
    
    outTexture.write(float4(result, 1.0), gid);
}

// --- 3. Face Sculpting (Warp) Shader ---
// Displaces pixels based on control points (Eyes, Nose, Jaw).
// Uses a Gaussian influence field for smooth warping.

struct ControlPoint {
    float2 position; // Normalized 0..1
    float2 displacement; // Delta in normalized coords
    float radius; // Influence radius
    float strength;
};

kernel void face_sculpt(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant ControlPoint *points [[buffer(0)]],
    constant int &pointCount [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 dim [[texture_dimensions(0)]]) 
{
    float2 uv = float2(gid) / float2(dim);
    float2 totalDisplacement = float2(0.0);
    
    // Accumulate displacement from all control points
    for (int i = 0; i < pointCount; i++) {
        ControlPoint p = points[i];
        float2 diff = uv - p.position;
        float distSq = dot(diff, diff);
        float radiusSq = p.radius * p.radius;
        
        if (distSq < radiusSq) {
            // Gaussian falloff
            float influence = exp(-distSq / (0.5 * radiusSq));
            totalDisplacement += p.displacement * influence * p.strength;
        }
    }
    
    // Sample source at displaced coordinate
    float2 sourceUV = uv + totalDisplacement;
    
    // Clamp to bounds
    sourceUV = clamp(sourceUV, 0.0, 1.0);
    uint2 sourceCoord = uint2(sourceUV * float2(dim));
    
    float4 color = inTexture.read(sourceCoord);
    outTexture.write(color, gid);
}

// Usage Example for Dart/Flutter integration:
// To widen eyes: Create a ControlPoint at eye center with displacement (-0.02, 0) for inner corner and (0.02, 0) for outer?
// Actually, simpler: One point per feature pushing pixels OUTWARD.
// Eye Enlarge: Point at center, displacement = (0,0) but strength pushes surrounding pixels away?
// Better approach for "Eye Size": 
//   Map destination UV back to source. 
//   If dest is near eye center, sample from further out (zoom out effect locally).
//   Formula: sourceUV = center + (uv - center) * (1.0 + strength);
