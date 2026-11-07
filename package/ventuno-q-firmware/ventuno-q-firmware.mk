################################################################################
#
# ventuno-q-firmware
#
################################################################################

VENTUNO_Q_FIRMWARE_VERSION = 20261019
VENTUNO_Q_FIRMWARE_BASE_URL = https://gitlab.com/kernel-firmware/linux-firmware/-/raw/$(VENTUNO_Q_FIRMWARE_VERSION)
VENTUNO_Q_FIRMWARE_SITE = $(VENTUNO_Q_FIRMWARE_BASE_URL)/LICENSES
VENTUNO_Q_FIRMWARE_SOURCE = LICENSE.qcom
VENTUNO_Q_FIRMWARE_LICENSE = Qualcomm firmware licences (redistributable)
VENTUNO_Q_FIRMWARE_LICENSE_FILES = LICENSE.qcom LICENSE.qcom-2 NOTICE.qcom LICENCE.linaro
VENTUNO_Q_FIRMWARE_REDISTRIBUTE = YES

VENTUNO_Q_FIRMWARE_QCS8300_FILES = \
	qupv3fw.elf a623_zap.mbn cdsp0.mbn cdspr.jsn arduino-monza-tplg.bin
# linux-firmware links these QCS8300 images to the SA8775P ones.
VENTUNO_Q_FIRMWARE_SA8775P_FILES = \
	adsp.mbn adspr.jsn adspua.jsn gpdsp0.mbn gpdspr.jsn
VENTUNO_Q_FIRMWARE_QCOM_FILES = a623_gmu.bin a650_sqe.fw

VENTUNO_Q_FIRMWARE_EXTRA_DOWNLOADS = \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/LICENSES/,LICENSE.qcom-2 NOTICE.qcom LICENCE.linaro) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/qcs8300/,$(VENTUNO_Q_FIRMWARE_QCS8300_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/sa8775p/,$(VENTUNO_Q_FIRMWARE_SA8775P_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/,$(VENTUNO_Q_FIRMWARE_QCOM_FILES))

define VENTUNO_Q_FIRMWARE_EXTRACT_CMDS
	cp $(VENTUNO_Q_FIRMWARE_DL_DIR)/* $(@D)/
endef

define VENTUNO_Q_FIRMWARE_INSTALL_TARGET_CMDS
	$(foreach f,$(VENTUNO_Q_FIRMWARE_QCS8300_FILES) $(VENTUNO_Q_FIRMWARE_SA8775P_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qcom/qcs8300/$(f)$(sep))
	$(foreach f,$(VENTUNO_Q_FIRMWARE_QCOM_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qcom/$(f)$(sep))
endef

$(eval $(generic-package))
