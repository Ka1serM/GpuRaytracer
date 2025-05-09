#pragma once

#include "Context.h"

class HdrToLdrCompute {
public:
    HdrToLdrCompute(Context &context, vk::ImageView inputImageView, vk::ImageView outputImageView);

    void dispatch(vk::CommandBuffer commandBuffer, uint32_t x, uint32_t y, uint32_t z);

private:
    Context& context;

    vk::UniqueShaderModule shaderModule;
    vk::UniqueDescriptorSetLayout descriptorSetLayout;
    vk::UniquePipelineLayout pipelineLayout;
    vk::UniquePipeline pipeline;
    vk::UniqueDescriptorPool descriptorPool;
    vk::UniqueDescriptorSet descriptorSet;
};
