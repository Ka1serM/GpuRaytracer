#version 460
#pragma shader_stage(raygen)

#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : enable

#include "SharedStructs.h"
#include "Common.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;
layout(binding = 1, set = 0, rgba32f) uniform image2D outputImage;
layout(binding = 5, set = 0) buffer Materials { Material materials[]; };
layout(binding = 6, set = 0) buffer PointLights { PointLight pointLights[]; };
layout(binding = 7, set = 0) uniform sampler2D textureSamplers[];

layout(push_constant) uniform PushConstants {
    PushData pushData;
    CameraData camera;
} pushConstants;

layout(location = 0) rayPayloadEXT PrimaryRayPayload payload;
layout(location = 1) rayPayloadEXT ShadowRayPayload shadowPayload;

void main() {
    ivec2 pixelCoord = ivec2(gl_LaunchIDEXT.xy);
    ivec2 screenSize = ivec2(gl_LaunchSizeEXT.xy);
    vec3 color = vec3(0.0);

    if (bool(pushConstants.pushData.isRayTracing)) {

        // Generate reproducible random jitter per pixel and frame
        uvec2 seed = pcg2d(uvec2(pixelCoord) ^ uvec2(pushConstants.pushData.frame * 16777619));
        vec2 jitter = vec2(rand(seed.x), rand(seed.y));

        // Jittered UV for anti-aliasing (optional — remove jitter for deterministic rays)
        vec2 uv = (vec2(pixelCoord) + jitter) / vec2(screenSize);
        uv.y = 1.0 - uv.y;

        // Ray origin and direction from camera
        vec3 rayOrigin = pushConstants.camera.position;
        vec3 rayDirection = normalize(
            pushConstants.camera.direction +
            pushConstants.camera.horizontal * (uv.x - 0.5) +
            pushConstants.camera.vertical * (uv.y - 0.5)
        );

        // Initialize payload
        payload.color = vec3(0.0);
        payload.normal = vec3(0.0);
        payload.position = vec3(0.0);
        payload.done = false;
        payload.throughput = vec3(1.0);

        // Trace primary ray
        traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 0, 0, 0, rayOrigin, 0.001, rayDirection, 10000.0, 0);

        // Accumulate color
        color = payload.color;
        vec3 position = payload.position;
        vec3 normal = normalize(payload.normal);

        // Shadow ray logic
        bool isShadowed = false;
        for (int i = 0; i < pointLights.length(); ++i) {
            PointLight light = pointLights[i];
            vec3 lightVec = light.position - position;
            float dist = length(lightVec);
            vec3 lightDir = normalize(lightVec);

            shadowPayload.hit = false;

            traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 2, 0, 2, position, 0.01, lightDir, dist, 1);

            if (shadowPayload.hit) {
                isShadowed = true;
                break;
            }
        }

        // Simple shadow attenuation
        if (isShadowed) {
            color *= 0.25;
        }
    }
    else {  // Path tracing

        vec2 jitter = vec2(0.0);

        // Generate a reproducible random seed based on pixel + frame
        uvec2 seed = pcg2d(uvec2(pixelCoord) ^ uvec2(pushConstants.pushData.frame * 16777619));
        uint seedX = seed.x;
        uint seedY = seed.y;

        jitter = vec2(rand(seedX), rand(seedY));

        vec2 screenPos = vec2(pixelCoord) + jitter;
        vec2 uv = screenPos / vec2(screenSize);
        uv.y = 1.0 - uv.y;

        vec3 rayOrigin = pushConstants.camera.position;
        vec3 rayDirection = normalize(
            pushConstants.camera.direction +
            pushConstants.camera.horizontal * (uv.x - 0.5) +
            pushConstants.camera.vertical * (uv.y - 0.5)
        );

        payload.color = vec3(0.0);
        payload.normal = vec3(0.0);
        payload.position = vec3(0.0);
        payload.done = false;
        payload.throughput = vec3(1.0);

        int maxDepth = 10;
        for (int depth = 0; depth < maxDepth; ++depth) {
            traceRayEXT(topLevelAS, gl_RayFlagsOpaqueEXT, 0xff, 1, 0, 1, rayOrigin, 0.001, rayDirection, 10000.0, 0);

            color += payload.throughput * payload.color;

            if (payload.done)
            break;

            rayOrigin = payload.position;
            rayDirection = sampleDirection(rand(seedX), rand(seedY), payload.normal);

            // Mutate the seed to ensure randomness in next iteration
            seedX ^= depth * 1664525u + 1013904223u;
            seedY ^= depth * 22695477u + 1u;
        }
    }

    vec3 prevColor = imageLoad(outputImage, pixelCoord).rgb;
    color = (color + prevColor * float(pushConstants.pushData.frame)) / float(pushConstants.pushData.frame + 1);

    imageStore(outputImage, pixelCoord, vec4(color, 1.0));
}