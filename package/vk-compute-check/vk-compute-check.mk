################################################################################
#
# vk-compute-check
#
################################################################################

VK_COMPUTE_CHECK_VERSION = 1.0
VK_COMPUTE_CHECK_SITE = $(NERVES_DEFCONFIG_DIR)/package/vk-compute-check/src
VK_COMPUTE_CHECK_SITE_METHOD = local
VK_COMPUTE_CHECK_LICENSE = Apache-2.0
VK_COMPUTE_CHECK_DEPENDENCIES = vulkan-headers vulkan-loader

define VK_COMPUTE_CHECK_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c11 -Wall -Wextra \
		-o $(@D)/vk-compute-check $(@D)/vk-compute-check.c -lvulkan
endef

define VK_COMPUTE_CHECK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/vk-compute-check $(TARGET_DIR)/usr/bin/vk-compute-check
endef

$(eval $(generic-package))
