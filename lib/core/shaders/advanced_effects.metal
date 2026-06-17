// Advanced Photo Editing Shaders
// Includes: Denoise, Dehaze, Lighting Injection, Face Sculpting

#import "metal_stdlib"
using namespace metal;

// --- Helper Functions ---

float luminance(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

// --- 1. Denoise (Bilateral Filter Approximation) ---
// Reduces noise while preserving edges by weighting neighbors based on spatial and color distance.
kernel void denoise_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                           texture2d<float, access::write> outTexture [[texture(1)]],
                           constant float &strength [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    
    int width = inTexture.get_width();
    int height = inTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) return;

    float3 centerColor = inTexture.read(gid).rgb;
    float3 accum = float3(0.0);
    float weightAccum = 0.0;
    
    int radius = 2; // Fixed radius for performance
    
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            int2 coord = int2(gid.x + x, gid.y + y);
            if (coord.x < 0 || coord.x >= width || coord.y < 0 || coord.y >= height) continue;
            
            float3 neighborColor = inTexture.read(coord).rgb;
            
            // Spatial weight
            float spatialDist = length(float2(x, y));
            float spatialWeight = exp(-spatialDist * spatialDist / (2.0 * 1.5 * 1.5));
            
            // Range weight (color similarity)
            float colorDist = length(centerColor - neighborColor);
            float rangeWeight = exp(-colorDist * colorDist / (2.0 * strength * strength));
            
            float totalWeight = spatialWeight * rangeWeight;
            
            accum += neighborColor * totalWeight;
            weightAccum += totalWeight;
        }
    }
    
    float3 result = accum / max(weightAccum, 0.0001);
    outTexture.write(float4(result, 1.0), gid);
}

// --- 2. Dehaze ---
// Based on Dark Channel Prior concept. Increases contrast in low-intensity channels.
kernel void dehaze_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                          texture2d<float, access::write> outTexture [[texture(1)]],
                          constant float &amount [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    
    int width = inTexture.get_width();
    int height = inTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) return;

    float3 color = inTexture.read(gid).rgb;
    
    // Simple dark channel approximation using local min (simplified for single pixel pass context)
    float darkChannel = min(min(color.r, color.g), color.b);
    
    // Transmission map estimation
    float transmission = 1.0 - amount * (1.0 - darkChannel);
    transmission = clamp(transmission, 0.1, 1.0);
    
    // Recover scene radiance
    float3 hazeColor = float3(0.8, 0.8, 0.8); // Atmospheric light assumption
    float3 result = (color - hazeColor * (1.0 - transmission)) / transmission;
    
    // Boost saturation slightly to compensate
    float lum = luminance(result);
    result = mix(float3(lum), result, 1.2);
    
    outTexture.write(float4(clamp(result, 0.0, 1.0), 1.0), gid);
}

// --- 3. Dynamic Lighting Injection ---
// Adds a light source at specific coordinates with color and intensity.
kernel void lighting_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            constant float2 &lightPos [[buffer(0)]], // Normalized 0-1
                            constant float3 &lightColor [[buffer(1)]],
                            constant float &intensity [[buffer(2)]],
                            constant float &radius [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
    
    int width = inTexture.get_width();
    int height = inTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) return;

    float3 color = inTexture.read(gid).rgb;
    
    // Calculate normalized coordinate
    float2 uv = float2(gid.x) / float2(width, height);
    
    // Distance from light source
    float dist = distance(uv, lightPos);
    
    // Falloff (smoothstep for soft edge)
    float attenuation = 1.0 - smoothstep(0.0, radius, dist);
    
    // Additive lighting blend
    float3 lightContribution = lightColor * intensity * attenuation;
    
    // Simple shading model: add light to existing color
    float3 result = color + lightContribution;
    
    outTexture.write(float4(clamp(result, 0.0, 1.0), 1.0), gid);
}

// --- 4. Face Sculpting (Warping) ---
// Uses distance fields to push/pull pixels around facial features.
// params: float4(x, y, radius, strength) for each feature
kernel void face_sculpt_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                               texture2d<float, access::write> outTexture [[texture(1)]],
                               constant float4 &eyeLeft [[buffer(0)]],
                               constant float4 &eyeRight [[buffer(1)]],
                               constant float4 &nose [[buffer(2)]],
                               constant float4 &mouth [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
    
    int width = inTexture.get_width();
    int height = inTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) return;

    float2 uv = float2(gid.x) / float2(width, height);
    uv.y = 1.0 - uv.y; 

    float2 finalUV = uv;

    auto applyWarp = [&](float4 zone) {
        float2 center = zone.xy;
        float radius = zone.z;
        float strength = zone.w;
        
        float dist = distance(uv, center);
        if (dist < radius) {
            float factor = smoothstep(radius, 0.0, dist);
            float2 direction = normalize(uv - center);
            finalUV -= direction * factor * strength * 0.05; 
        }
    };

    applyWarp(eyeLeft);
    applyWarp(eyeRight);
    applyWarp(nose);
    applyWarp(mouth);

    float2 sampleCoord = float2(finalUV.x * width, (1.0 - finalUV.y) * height);
    
    int2 coord = int2(sampleCoord);
    if (coord.x >= 0 && coord.x < width && coord.y >= 0 && coord.y < height) {
        outTexture.write(inTexture.read(coord), gid);
    } else {
        outTexture.write(float4(0,0,0,1), gid);
    }
}
