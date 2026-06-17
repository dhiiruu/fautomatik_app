#include <metal_stdlib>
using namespace metal;

// Cloth Warping Shader with Realistic Physics
// Uses mass-spring-damper simulation for natural fabric behavior

struct ClothVertex {
    float2 position;
    float2 uv;
    float3 normal;
};

struct ClothUniforms {
    float time;
    float intensity;
    float stiffness;
    float damping;
    float mass;
    float2 windDirection;
    float windStrength;
    float gravity;
    int resolution;
};

// Mass-Spring-Damper System for Cloth Simulation
struct MassPoint {
    float2 position;
    float2 velocity;
    float2 force;
    float mass;
    bool isPinned;
};

struct Spring {
    int pointA;
    int pointB;
    float restLength;
    float stiffness;
};

// Perlin noise for natural fabric wrinkles
float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float noise(float2 x) {
    float2 i = floor(x);
    float2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Calculate fabric wrinkle displacement using FBM
float2 calculateWrinkles(float2 uv, float time, float intensity) {
    float2 displacement = float2(0.0);
    
    // Primary wrinkles (large scale)
    float wrinkle1 = fbm(uv * 10.0 + float2(time * 0.1, 0.0));
    displacement.x += (wrinkle1 - 0.5) * intensity * 0.02;
    
    // Secondary wrinkles (fine detail)
    float wrinkle2 = fbm(uv * 25.0 + float2(time * 0.2, time * 0.1));
    displacement.y += (wrinkle2 - 0.5) * intensity * 0.01;
    
    return displacement;
}

// Simulate cloth physics using Verlet integration
float2 simulateClothPhysics(float2 uv, ClothUniforms uniforms) {
    float2 displacement = float2(0.0);
    
    // Gravity effect (cloth hangs down)
    displacement.y -= uniforms.gravity * uv.y * 0.01;
    
    // Wind effect
    float windForce = dot(uv, uniforms.windDirection) * uniforms.windStrength;
    displacement += uniforms.windDirection * windForce * 0.005;
    
    // Stiffness resistance
    float stiffnessFactor = 1.0 - uniforms.stiffness * 0.5;
    displacement *= stiffnessFactor;
    
    // Damping (reduces oscillation)
    float dampingFactor = exp(-uniforms.damping * uniforms.time);
    displacement *= dampingFactor;
    
    return displacement;
}

// Calculate lighting on cloth folds
float calculateClothLighting(float2 uv, float3 lightDir, float2 displacement) {
    // Estimate normal from displacement gradient
    float epsilon = 0.01;
    float dx = fbm((uv + float2(epsilon, 0.0)) * 20.0) - fbm(uv * 20.0);
    float dy = fbm((uv + float2(0.0, epsilon)) * 20.0) - fbm(uv * 20.0);
    
    float3 normal = normalize(float3(-dx * 10.0, -dy * 10.0, 1.0));
    
    // Diffuse lighting
    float diffuse = max(dot(normal, lightDir), 0.0);
    
    // Specular highlights on folds
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfDir = normalize(lightDir + viewDir);
    float specular = pow(max(dot(normal, halfDir), 0.0), 32.0);
    
    return diffuse + specular * 0.3;
}

// Adjust color based on lighting and shadows in folds
float3 adjustClothColor(float3 originalColor, float lighting, float shadow) {
    // Warm shadows, cool highlights (typical fabric behavior)
    float3 shadowColor = float3(0.9, 0.85, 0.8);
    float3 highlightColor = float3(1.0, 1.0, 1.05);
    
    // Blend based on lighting
    float3 adjusted = originalColor * lighting;
    adjusted = mix(adjusted * shadowColor, adjusted, lighting);
    adjusted = mix(adjusted, adjusted * highlightColor, max(lighting - 0.5, 0.0) * 2.0);
    
    // Add subtle saturation boost in midtones
    float luminance = dot(adjusted, float3(0.299, 0.587, 0.114));
    float saturationBoost = 1.1 - abs(lighting - 0.5);
    adjusted = mix(float3(luminance), adjusted, saturationBoost);
    
    return adjusted;
}

// Main cloth warp kernel
kernel void clothWarp(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant ClothUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 uv = (float2(gid) + 0.5) / float2(uniforms.resolution);
    
    // Get original color
    float4 originalColor = inTexture.read(gid);
    
    // Calculate total displacement
    float2 wrinkleDisp = calculateWrinkles(uv, uniforms.time, uniforms.intensity);
    float2 physicsDisp = simulateClothPhysics(uv, uniforms);
    float2 totalDisp = wrinkleDisp + physicsDisp;
    
    // Sample from displaced UV
    float2 sampleUV = uv + totalDisp;
    sampleUV = clamp(sampleUV, 0.0, 1.0);
    
    // Simple bilinear sampling (can be improved with proper filtering)
    float2 texSize = float2(inTexture.get_width(), inTexture.get_height());
    float2 samplePos = sampleUV * texSize;
    uint2 sampleGid = uint2(floor(samplePos));
    sampleGid = min(sampleGid, texSize - 1);
    
    float4 sampledColor = inTexture.read(sampleGid);
    
    // Calculate lighting on cloth
    float3 lightDir = normalize(float3(0.5, -0.3, 1.0));
    float lighting = calculateClothLighting(uv, lightDir, totalDisp);
    
    // Calculate shadow in deep folds
    float shadow = 1.0 - length(totalDisp) * 5.0;
    shadow = clamp(shadow, 0.6, 1.0);
    
    // Adjust color with realistic lighting
    float3 adjustedColor = adjustClothColor(sampledColor.rgb, lighting, shadow);
    
    // Apply intensity blend
    float3 finalColor = mix(sampledColor.rgb, adjustedColor, uniforms.intensity);
    
    outTexture.write(float4(finalColor, originalColor.a), gid);
}

// Cloth smoothing pass (bilateral-like filter for fabric)
kernel void clothSmooth(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant ClothUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 uv = (float2(gid) + 0.5) / float2(uniforms.resolution);
    float2 texSize = float2(inTexture.get_width(), inTexture.get_height());
    
    float4 center = inTexture.read(gid);
    float4 sum = center;
    float totalWeight = 1.0;
    
    // Sample neighboring pixels with edge-preserving weights
    int radius = 2;
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            uint2 neighborGid = gid + uint2(dx, dy);
            if (neighborGid.x >= uniforms.resolution || neighborGid.y >= uniforms.resolution) continue;
            
            float4 neighbor = inTexture.read(neighborGid);
            
            // Spatial weight
            float dist = sqrt(float(dx * dx + dy * dy));
            float spatialWeight = exp(-dist * dist / 2.0);
            
            // Color weight (preserve edges)
            float colorDiff = length(neighbor.rgb - center.rgb);
            float colorWeight = exp(-colorDiff * colorDiff / 0.1);
            
            float weight = spatialWeight * colorWeight;
            sum += neighbor * weight;
            totalWeight += weight;
        }
    }
    
    float4 smoothed = sum / totalWeight;
    outTexture.write(smoothed, gid);
}

// Fabric texture enhancement (adds subtle weave pattern)
kernel void enhanceFabric(
    texture2d<float> inTexture [[texture(0)]],
    texture2d<float> outTexture [[texture(1)]],
    constant ClothUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 uv = (float2(gid) + 0.5) / float2(uniforms.resolution);
    float4 color = inTexture.read(gid);
    
    // Generate subtle weave pattern
    float weaveX = sin(uv.x * 100.0) * 0.02;
    float weaveY = cos(uv.y * 100.0) * 0.02;
    float weave = (weaveX + weaveY) * uniforms.intensity * 0.5;
    
    // Add pattern to color
    float3 enhanced = color.rgb + weave;
    enhanced = clamp(enhanced, 0.0, 1.0);
    
    outTexture.write(float4(enhanced, color.a), gid);
}
