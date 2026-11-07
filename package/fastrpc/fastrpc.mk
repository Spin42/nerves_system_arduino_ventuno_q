################################################################################
#
# fastrpc
#
################################################################################

FASTRPC_VERSION = 1.0.8
FASTRPC_SITE = $(call github,qualcomm,fastrpc,v$(FASTRPC_VERSION))
FASTRPC_LICENSE = BSD-3-Clause
FASTRPC_LICENSE_FILES = LICENSE.txt
FASTRPC_INSTALL_STAGING = YES
FASTRPC_AUTORECONF = YES
FASTRPC_DEPENDENCIES = host-pkgconf libbsd libyaml
FASTRPC_CONF_OPTS = \
	--with-config-base-dir=/usr/share/qcom \
	--with-systemdsystemunitdir=/usr/lib/systemd/system \
	--with-udevrulesdir=/usr/lib/udev/rules.d \
	--with-sysusersdir=/usr/lib/sysusers.d

$(eval $(autotools-package))
