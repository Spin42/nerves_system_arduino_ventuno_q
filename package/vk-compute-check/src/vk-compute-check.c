/*
 * Runs one compute shader on the first Vulkan device and checks its output:
 * every element i of a buffer becomes 2 * i + 1. Prints the device and "ok",
 * and exits 0 when the GPU computed every element.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

#include "double.spv.h"

#define COUNT (64 * 1024)

#define CHECK(call)                                                        \
    do {                                                                   \
        VkResult result_ = (call);                                         \
        if (result_ != VK_SUCCESS) {                                       \
            fprintf(stderr, "%s failed: %d\n", #call, (int)result_);       \
            return 1;                                                      \
        }                                                                  \
    } while (0)

int main(void)
{
    VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                             .pApplicationName = "vk-compute-check",
                             .apiVersion = VK_API_VERSION_1_1};
    VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                                          .pApplicationInfo = &app};
    VkInstance instance;
    CHECK(vkCreateInstance(&instance_info, NULL, &instance));

    uint32_t device_count = 1;
    VkPhysicalDevice physical;
    VkResult enumerated = vkEnumeratePhysicalDevices(instance, &device_count, &physical);
    if ((enumerated != VK_SUCCESS && enumerated != VK_INCOMPLETE) || device_count == 0) {
        fprintf(stderr, "no Vulkan device\n");
        return 1;
    }

    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(physical, &properties);
    printf("device: %s\n", properties.deviceName);

    uint32_t family_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &family_count, NULL);
    VkQueueFamilyProperties families[16];
    if (family_count > 16)
        family_count = 16;
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &family_count, families);
    uint32_t family = UINT32_MAX;
    for (uint32_t i = 0; i < family_count; i++)
        if (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            family = i;
            break;
        }
    if (family == UINT32_MAX) {
        fprintf(stderr, "no compute queue\n");
        return 1;
    }

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                          .queueFamilyIndex = family,
                                          .queueCount = 1,
                                          .pQueuePriorities = &priority};
    VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                                      .queueCreateInfoCount = 1,
                                      .pQueueCreateInfos = &queue_info};
    VkDevice device;
    CHECK(vkCreateDevice(physical, &device_info, NULL, &device));
    VkQueue queue;
    vkGetDeviceQueue(device, family, 0, &queue);

    VkDeviceSize size = COUNT * sizeof(uint32_t);
    VkBufferCreateInfo buffer_info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                                      .size = size,
                                      .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                                      .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
    VkBuffer buffer;
    CHECK(vkCreateBuffer(device, &buffer_info, NULL, &buffer));

    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(device, buffer, &requirements);
    VkPhysicalDeviceMemoryProperties memory_properties;
    vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
    VkMemoryPropertyFlags wanted =
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    uint32_t memory_type = UINT32_MAX;
    for (uint32_t i = 0; i < memory_properties.memoryTypeCount; i++)
        if ((requirements.memoryTypeBits & (1u << i)) &&
            (memory_properties.memoryTypes[i].propertyFlags & wanted) == wanted) {
            memory_type = i;
            break;
        }
    if (memory_type == UINT32_MAX) {
        fprintf(stderr, "no host-visible memory\n");
        return 1;
    }
    VkMemoryAllocateInfo allocate_info = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                                          .allocationSize = requirements.size,
                                          .memoryTypeIndex = memory_type};
    VkDeviceMemory memory;
    CHECK(vkAllocateMemory(device, &allocate_info, NULL, &memory));
    CHECK(vkBindBufferMemory(device, buffer, memory, 0));

    uint32_t *values;
    CHECK(vkMapMemory(device, memory, 0, size, 0, (void **)&values));
    memset(values, 0, size);

    VkShaderModuleCreateInfo shader_info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                                            .codeSize = sizeof(double_spv),
                                            .pCode = double_spv};
    VkShaderModule shader;
    CHECK(vkCreateShaderModule(device, &shader_info, NULL, &shader));

    VkDescriptorSetLayoutBinding binding = {.binding = 0,
                                            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                            .descriptorCount = 1,
                                            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
    VkDescriptorSetLayoutCreateInfo set_layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding};
    VkDescriptorSetLayout set_layout;
    CHECK(vkCreateDescriptorSetLayout(device, &set_layout_info, NULL, &set_layout));

    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &set_layout};
    VkPipelineLayout pipeline_layout;
    CHECK(vkCreatePipelineLayout(device, &pipeline_layout_info, NULL, &pipeline_layout));

    VkComputePipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                  .stage = VK_SHADER_STAGE_COMPUTE_BIT,
                  .module = shader,
                  .pName = "main"},
        .layout = pipeline_layout};
    VkPipeline pipeline;
    CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &pipeline));

    VkDescriptorPoolSize pool_size = {.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                      .descriptorCount = 1};
    VkDescriptorPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
                                            .maxSets = 1,
                                            .poolSizeCount = 1,
                                            .pPoolSizes = &pool_size};
    VkDescriptorPool pool;
    CHECK(vkCreateDescriptorPool(device, &pool_info, NULL, &pool));
    VkDescriptorSetAllocateInfo set_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                                            .descriptorPool = pool,
                                            .descriptorSetCount = 1,
                                            .pSetLayouts = &set_layout};
    VkDescriptorSet set;
    CHECK(vkAllocateDescriptorSets(device, &set_info, &set));
    VkDescriptorBufferInfo descriptor_buffer = {.buffer = buffer, .range = VK_WHOLE_SIZE};
    VkWriteDescriptorSet write = {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                                  .dstSet = set,
                                  .descriptorCount = 1,
                                  .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                                  .pBufferInfo = &descriptor_buffer};
    vkUpdateDescriptorSets(device, 1, &write, 0, NULL);

    VkCommandPoolCreateInfo command_pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                                 .queueFamilyIndex = family};
    VkCommandPool command_pool;
    CHECK(vkCreateCommandPool(device, &command_pool_info, NULL, &command_pool));
    VkCommandBufferAllocateInfo command_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1};
    VkCommandBuffer commands;
    CHECK(vkAllocateCommandBuffers(device, &command_info, &commands));

    VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                                      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
    CHECK(vkBeginCommandBuffer(commands, &begin));
    vkCmdBindPipeline(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 1, &set,
                            0, NULL);
    vkCmdDispatch(commands, COUNT / 64, 1, 1);
    VkMemoryBarrier barrier = {.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
                               .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
                               .dstAccessMask = VK_ACCESS_HOST_READ_BIT};
    vkCmdPipelineBarrier(commands, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
                         0, 1, &barrier, 0, NULL, 0, NULL);
    CHECK(vkEndCommandBuffer(commands));

    VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                           .commandBufferCount = 1,
                           .pCommandBuffers = &commands};
    CHECK(vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE));
    CHECK(vkQueueWaitIdle(queue));

    for (uint32_t i = 0; i < COUNT; i++)
        if (values[i] != i * 2u + 1u) {
            printf("mismatch at %u: %u\n", i, values[i]);
            return 1;
        }

    printf("ok: %u values\n", COUNT);
    return 0;
}
