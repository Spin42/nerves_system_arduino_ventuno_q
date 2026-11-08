################################################################################
#
# arduino-zephyr-loader
#
################################################################################

# arduino:zephyr 1.1.0 in Arduino's package index
ARDUINO_ZEPHYR_LOADER_VERSION = f07865dd
ARDUINO_ZEPHYR_LOADER_SITE = https://downloads.arduino.cc/cores/zephyr
ARDUINO_ZEPHYR_LOADER_SOURCE = ArduinoCore-zephyr_unoq-$(ARDUINO_ZEPHYR_LOADER_VERSION).tar.bz2
ARDUINO_ZEPHYR_LOADER_LICENSE = Apache-2.0
ARDUINO_ZEPHYR_LOADER_LICENSE_FILES = LICENSE

define ARDUINO_ZEPHYR_LOADER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/firmwares/zephyr-arduino_ventuno_q_stm32h5f5xx.bin \
		$(TARGET_DIR)/usr/share/ventuno-q/mcu-loader.bin
endef

$(eval $(generic-package))
