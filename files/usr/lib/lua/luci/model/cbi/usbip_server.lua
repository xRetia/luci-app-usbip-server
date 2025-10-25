local i18n = luci.i18n.translate

m = Map("usbip_server", i18n("USBIP Server Configuration"),
    i18n([[Share your OpenWRT USB devices over TCP/IP network. 
    Install <a href="https://github.com/vadimgrn/usbip-win2" target="_blank">usbip-win2</a> 
    client software on your Windows computers. 
    This package is generated with DeepSeek AI technology.]]))

m:section(SimpleSection).template = "usbip_server/status"

s = m:section(TypedSection, "config", i18n("Server Settings"))
s.anonymous = true
s.addremove = false

enabled = s:option(Flag, "enabled", i18n("Enable USBIP Server"),
    i18n("Enable USBIP server and device monitoring"))
enabled.default = "0"
enabled.rmempty = false

port = s:option(Value, "server_port", i18n("Server Port"),
    i18n("TCP port for USBIP server (default: 3240)"))
port.default = "3240"
port.datatype = "port"
port.optional = false

mode = s:option(ListValue, "registration_mode", i18n("Device Registration"),
    i18n("Control which USB devices are automatically shared"))
mode:value("all", i18n("All Devices"))
mode:value("whitelist", i18n("Specific Devices (Whitelist)"))
mode:value("blacklist", i18n("All Except Specific Devices (Blacklist)"))
mode.default = "all"

devices = s:option(DynamicList, "device_list", i18n("USB Devices"),
    i18n("Select USB devices to include/exclude based on registration mode above"))
devices:depends("registration_mode", "whitelist")
devices:depends("registration_mode", "blacklist")

m:section(SimpleSection).template = "usbip_server/devices"

return m