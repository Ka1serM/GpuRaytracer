#version 460
#pragma shader_stage(compute)

layout(local_size_x = 16, local_size_y = 16) in;

layout(binding = 0, rgba32f) readonly uniform image2D inputImage;
layout(binding = 1, rgba8) writeonly uniform image2D outputImage;

vec3 aces_approx(vec3 v)
{
    v *= 0.6f;
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((v*(a*v+b))/(v*(c*v+d)+e), 0.0f, 1.0f);
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);

    vec4 color = imageLoad(inputImage, coord);
    vec4 acesColor = vec4(aces_approx(color.rgb), 1.0f);
    imageStore(outputImage, coord, acesColor);
}