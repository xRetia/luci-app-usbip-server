local i18n = luci.i18n.translate
local sys = require "luci.sys"
local uci = require "luci.model.uci"

local ucic = uci.cursor()
if not ucic:get("usbip_server", "config") then
    ucic:section("usbip_server", "config", nil, {
        enabled = "0",
        registration_mode = "all",
        device_list = "",
        server_port = "3240",
        auto_bind = "1"
    })
    ucic:commit("usbip_server")
end

m = Map("usbip_server", i18n("USBIP Server Configuration"),
    i18n([[Share your OpenWRT USB devices over TCP/IP network. 
    Install <a href="https://github.com/vadimgrn/usbip-win2" target="_blank">usbip-win2</a> 
    client software on your Windows computers. 
    This package is generated with DeepSeek AI technology.]]))

function m.on_after_commit(self)
    local ucic = uci.cursor()
    local is_enabled = ucic:get_bool("usbip_server", "config", "enabled")
    
    if not is_enabled then
        sys.call("/etc/init.d/usbip_monitor stop")
        sys.call("/etc/init.d/usbip_monitor disable")
    else
        sys.call("/etc/init.d/usbip_monitor enable")
        
        local running = sys.call("/etc/init.d/usbip_monitor status >/dev/null 2>&1") == 0
        if running then
            sys.call("/etc/init.d/usbip_monitor restart")
        else
            sys.call("/etc/init.d/usbip_monitor start")
        end
    end
end

m:section(SimpleSection).template = "usbip_server/status"

s = m:section(TypedSection, "config", i18n("Server Settings"))
s.anonymous = true
s.addremove = false

s.cfgsections = function()
    return { "config" }
end

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

function get_usb_devices()
    local devices = {}
    local sysfs_devices = sys.exec("ls /sys/bus/usb/devices/ 2>/dev/null | grep -E '^[0-9]+-[0-9]+(\\.[0-9]+)*$'")
    
    local ucic = uci.cursor()
    local configured_devices = ucic:get_list("usbip_server", "config", "device_list")
    local detected_devices = {}
    
    -- 修复正则表达式，使用正确的方式处理换行符
    for device in string.gmatch(sysfs_devices, "[^\n]+") do
        local vendor = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idVendor 2>/dev/null", device)) or "unknown"
        local product = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idProduct 2>/dev/null", device)) or "unknown"
        local manufacturer = sys.exec(string.format("cat /sys/bus/usb/devices/%s/manufacturer 2>/dev/null", device)) or i18n("unknown vendor")
        local product_name = sys.exec(string.format("cat /sys/bus/usb/devices/%s/product 2>/dev/null", device)) or i18n("unknown product")
        
        vendor = vendor:gsub("%s+", "")
        product = product:gsub("%s+", "")
        manufacturer = manufacturer:gsub("^%s*(.-)%s*$", "%1")
        product_name = product_name:gsub("^%s*(.-)%s*$", "%1")
        
        local display_name = string.format("%s - %s %s (%s:%s)", device, manufacturer, product_name, vendor, product)
        
        devices[device] = display_name
        detected_devices[device] = true
    end
    
    for _, busid in ipairs(configured_devices) do
        if not detected_devices[busid] then
            devices[busid] = string.format("%s - %s", busid, i18n("Plugged out"))
        end
    end
    
    return devices
end

devices = s:option(DynamicList, "device_list", i18n("USB Devices"),
    i18n("Select USB devices to include/exclude based on registration mode above") .. " " .. i18n("Format: BusID - Vendor Product (VID:PID)"))
devices:depends("registration_mode", "whitelist")
devices:depends("registration_mode", "blacklist")

devices.widget = "combobox"
devices.cast = nil

local usb_devices = get_usb_devices()
for busid, display_name in pairs(usb_devices) do
    devices:value(busid, display_name)
end

return m