include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-usbip-server
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_MAINTAINER:=DeepSeek AI
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=USBIP Server for OpenWRT
  DEPENDS:=+usbip +usbip-server +usbip-client +kmod-usbip +kmod-usbip-client +kmod-usbip-server +lua +luci-base +luci-compat
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  LuCI interface for USBIP Server - Share USB devices over TCP/IP network.
  This package allows you to use your OpenWRT device as a USB server, 
  sharing USB devices with remote clients. Generated with DeepSeek AI technology.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/usbip_server $(1)/etc/config/usbip_server
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/usbip_monitor $(1)/etc/init.d/usbip_monitor
	
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/usbip_monitor.sh $(1)/usr/bin/usbip_monitor.sh
	
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/usbip_server.lua $(1)/usr/lib/lua/luci/controller/usbip_server.lua
	
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/usbip_server.lua $(1)/usr/lib/lua/luci/model/cbi/usbip_server.lua
	
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/usbip_server
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/usbip_server/status.htm $(1)/www/luci-static/resources/view/usbip_server/status.htm
	
	# Install internationalization files
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) ./po/zh_Hans/usbip_server.po $(1)/usr/lib/lua/luci/i18n/
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# Disable the original usbipd service to avoid conflicts
	if [ -f /etc/init.d/usbipd ]; then
	    /etc/init.d/usbipd disable
	    /etc/init.d/usbipd stop
	fi
	
	# Enable and start our monitor service
	/etc/init.d/usbip_monitor enable
	/etc/init.d/usbip_monitor start
	
	# Display installation information
	echo "USBIP Server installed successfully!"
	echo "Original usbipd service has been disabled to avoid conflicts."
	echo "Please install required kernel modules:"
	echo "opkg update && opkg install usbip usbip-server usbip-client kmod-usbip kmod-usbip-client kmod-usbip-server"
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# Stop our services
	/etc/init.d/usbip_monitor stop
	/etc/init.d/usbip_monitor disable
	
	# Note: We don't re-enable the original usbipd service automatically
	# to avoid unexpected behavior during upgrades
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))