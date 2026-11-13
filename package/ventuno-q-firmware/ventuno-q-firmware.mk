################################################################################
#
# ventuno-q-firmware
#
################################################################################

VENTUNO_Q_FIRMWARE_VERSION = 20261019
VENTUNO_Q_FIRMWARE_BASE_URL = https://gitlab.com/kernel-firmware/linux-firmware/-/raw/$(VENTUNO_Q_FIRMWARE_VERSION)
VENTUNO_Q_FIRMWARE_SITE = $(VENTUNO_Q_FIRMWARE_BASE_URL)/LICENSES
VENTUNO_Q_FIRMWARE_SOURCE = LICENSE.qcom
VENTUNO_Q_FIRMWARE_LICENSE = Qualcomm and Qualcomm Atheros firmware licences (redistributable)
VENTUNO_Q_FIRMWARE_LICENSE_FILES = LICENSE.qcom LICENSE.qcom-2 NOTICE.qcom LICENCE.linaro \
	LICENSE.QualcommAtheros_ath10k NOTICE.qca
VENTUNO_Q_FIRMWARE_REDISTRIBUTE = YES

VENTUNO_Q_FIRMWARE_QCS8300_FILES = \
	qupv3fw.elf a623_zap.mbn cdsp0.mbn cdspr.jsn arduino-monza-tplg.bin
# linux-firmware links these QCS8300 images to the SA8775P ones.
VENTUNO_Q_FIRMWARE_SA8775P_FILES = \
	adsp.mbn adspr.jsn adspua.jsn gpdsp0.mbn gpdspr.jsn
VENTUNO_Q_FIRMWARE_QCOM_FILES = a623_gmu.bin a650_sqe.fw
# The Iris video codec's firmware, its H.264 and HEVC encoder and decoder.
VENTUNO_Q_FIRMWARE_VPU_FILES = vpu30_p4_s6.mbn
# The QCA2066 Bluetooth patch and the NVM file for the board's ID (0x30c,
# GlobalFoundries silicon).
VENTUNO_Q_FIRMWARE_QCA_FILES = hpbtfw21.tlv hpnv21g.30c
# The QCA2066 Wi-Fi firmware for ath11k.
VENTUNO_Q_FIRMWARE_ATH11K_FILES = amss.bin m3.bin board-2.bin Notice.txt

VENTUNO_Q_FIRMWARE_EXTRA_DOWNLOADS = \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/LICENSES/,LICENSE.qcom-2 NOTICE.qcom LICENCE.linaro \
		LICENSE.QualcommAtheros_ath10k NOTICE.qca) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/qcs8300/,$(VENTUNO_Q_FIRMWARE_QCS8300_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/sa8775p/,$(VENTUNO_Q_FIRMWARE_SA8775P_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/,$(VENTUNO_Q_FIRMWARE_QCOM_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qcom/vpu/,$(VENTUNO_Q_FIRMWARE_VPU_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/qca/,$(VENTUNO_Q_FIRMWARE_QCA_FILES)) \
	$(addprefix $(VENTUNO_Q_FIRMWARE_BASE_URL)/ath11k/QCA2066/hw2.1/,$(VENTUNO_Q_FIRMWARE_ATH11K_FILES))

define VENTUNO_Q_FIRMWARE_EXTRACT_CMDS
	cp $(VENTUNO_Q_FIRMWARE_DL_DIR)/* $(@D)/
endef

define VENTUNO_Q_FIRMWARE_INSTALL_TARGET_CMDS
	$(foreach f,$(VENTUNO_Q_FIRMWARE_QCS8300_FILES) $(VENTUNO_Q_FIRMWARE_SA8775P_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qcom/qcs8300/$(f)$(sep))
	$(foreach f,$(VENTUNO_Q_FIRMWARE_QCOM_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qcom/$(f)$(sep))
	$(foreach f,$(VENTUNO_Q_FIRMWARE_VPU_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qcom/vpu/$(f)$(sep))
	$(foreach f,$(VENTUNO_Q_FIRMWARE_QCA_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/qca/$(f)$(sep))
	$(foreach f,$(VENTUNO_Q_FIRMWARE_ATH11K_FILES), \
		$(INSTALL) -D -m 0644 $(@D)/$(f) $(TARGET_DIR)/lib/firmware/ath11k/QCA2066/hw2.1/$(f)$(sep))
endef

$(eval $(generic-package))
