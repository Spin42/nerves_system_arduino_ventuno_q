################################################################################
#
# openocd-stm32
#
################################################################################

OPENOCD_STM32_VERSION = openocd-cubeide-r7
OPENOCD_STM32_SITE = $(call github,STMicroelectronics,OpenOCD,$(OPENOCD_STM32_VERSION))
OPENOCD_STM32_LICENSE = GPL-2.0+
OPENOCD_STM32_LICENSE_FILES = COPYING
OPENOCD_STM32_AUTORECONF = YES
OPENOCD_STM32_DEPENDENCIES = host-pkgconf jimtcl libgpiod

# Several sources rely on jim.h including stdio.h, which jimtcl 0.83's does not.
OPENOCD_STM32_CONF_ENV = CFLAGS="$(TARGET_CFLAGS) -include stdio.h"

OPENOCD_STM32_CONF_OPTS = \
	--disable-doxygen-html \
	--disable-internal-jimtcl \
	--disable-internal-libjaylink \
	--disable-werror \
	--enable-linuxgpiod

$(eval $(autotools-package))
