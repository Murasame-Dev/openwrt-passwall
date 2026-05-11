include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wol-ws
PKG_VERSION:=1.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for WebSocket/HTTP WOL Server/Client
LUCI_DEPENDS:=+luasocket +luasec +lua-websockets-copas +etherwake +lua +luci-lib-jsonc
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
