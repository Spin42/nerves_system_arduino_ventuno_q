################################################################################
#
# hexagon-dsp-binaries
#
################################################################################

HEXAGON_DSP_BINARIES_VERSION = 20261019
HEXAGON_DSP_BINARIES_SITE = https://github.com/linux-msm/dsp-binaries.git
HEXAGON_DSP_BINARIES_SITE_METHOD = git
HEXAGON_DSP_BINARIES_LICENSE = Qualcomm firmware licence (redistributable), MIT (configuration)
HEXAGON_DSP_BINARIES_LICENSE_FILES = LICENSE.qcom-2 LICENSE.MIT WHENCE
HEXAGON_DSP_BINARIES_REDISTRIBUTE = YES

# config.txt installs this directory as the board's dsp/cdsp. Its version
# matches qcom/qcs8300/cdsp0.mbn from linux-firmware.
HEXAGON_DSP_BINARIES_CDSP = qcs8300/Qualcomm/QCS8300-RIDE/cdsp-DSP.AT.1.0.1-00204-LEMANS-1
HEXAGON_DSP_BINARIES_DEST = $(TARGET_DIR)/usr/share/qcom

define HEXAGON_DSP_BINARIES_INSTALL_TARGET_CMDS
	mkdir -p $(HEXAGON_DSP_BINARIES_DEST)/qcs8300/Arduino/Monza/dsp/cdsp \
		$(HEXAGON_DSP_BINARIES_DEST)/conf.d
	cp -a $(@D)/$(HEXAGON_DSP_BINARIES_CDSP)/. \
		$(HEXAGON_DSP_BINARIES_DEST)/qcs8300/Arduino/Monza/dsp/cdsp/
	$(INSTALL) -m 0644 $(@D)/conf.d/hexagon-dsp-binaries-arduino-monza.yaml \
		$(@D)/conf.d/schema.json $(HEXAGON_DSP_BINARIES_DEST)/conf.d/
endef

$(eval $(generic-package))
