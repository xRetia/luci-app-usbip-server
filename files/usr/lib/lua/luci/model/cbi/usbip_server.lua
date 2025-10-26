local i18n = luci.i18n.translate
local sys = require "luci.sys"
local uci = require "luci.model.uci"

-- Ensure configuration exists
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

-- Create Map object
m = Map("usbip_server", i18n("USBIP Server Configuration"),
    i18n([[Share your OpenWRT USB devices over TCP/IP network. 
    Install <a href="https://github.com/vadimgrn/usbip-win2" target="_blank">usbip-win2</a> 
    client software on your Windows computers. 
    This package is generated with DeepSeek AI technology.]]))

-- Add post-commit handler to restart service
function m.on_after_commit(self)
    local ucic = uci.cursor()
    local is_enabled = ucic:get_bool("usbip_server", "config", "enabled")
    
    if not is_enabled then
        -- If disabled, stop and disable the service
        sys.call("/etc/init.d/usbip_monitor stop")
        sys.call("/etc/init.d/usbip_monitor disable")
    else
        -- If enabled, enable and start the service
        sys.call("/etc/init.d/usbip_monitor enable")
        
        -- Check if service is already running before restarting
        local running = sys.call("/etc/init.d/usbip_monitor status >/dev/null 2>&1") == 0
        if running then
            sys.call("/etc/init.d/usbip_monitor restart")
        else
            sys.call("/etc/init.d/usbip_monitor start")
        end
    end
end

-- Add status template
m:section(SimpleSection).template = "usbip_server/status"

-- Use TypedSection with correct configuration type
s = m:section(TypedSection, "config", i18n("Server Settings"))
s.anonymous = true
s.addremove = false

-- Ensure config section exists
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

-- Function to get USB devices from sysfs
function get_usb_devices()
    local devices = {}
    local sysfs_devices = sys.exec("ls /sys/bus/usb/devices/ 2>/dev/null | grep -E '^[0-9]+-[0-9]+(\\.[0-9]+)*$'")
    
    for device in sysfs_devices:gmatch("[^\n]+") do
        local vendor = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idVendor 2>/dev/null", device)) or "unknown"
        local product = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idProduct 2>/dev/null", device)) or "unknown"
        local manufacturer = sys.exec(string.format("cat /sys/bus/usb/devices/%s/manufacturer 2>/dev/null", device)) or i18n("unknown vendor")
        local product_name = sys.exec(string.format("cat /sys/bus/usb/devices/%s/product 2>/dev/null", device)) or i18n("unknown product")
        
        -- Clean up strings
        vendor = vendor:gsub("%s+", "")
        product = product:gsub("%s+", "")
        manufacturer = manufacturer:gsub("^%s*(.-)%s*$", "%1")
        product_name = product_name:gsub("^%s*(.-)%s*$", "%1")
        
        -- Create display name
        local display_name = string.format("%s - %s %s", device, manufacturer, product_name)
        
        -- Add to devices table
        devices[device] = display_name
    end
    
    return devices
end

-- Create device list as DynamicList with dropdown options
devices = s:option(DynamicList, "device_list", i18n("USB Devices"),
    i18n("Select USB devices to include/exclude based on registration mode above"))
devices:depends("registration_mode", "whitelist")
devices:depends("registration_mode", "blacklist")

-- Set up dropdown options for DynamicList
devices.widget = "combobox"
devices.cast = nil -- Allow free-form input but show dropdown options

-- Populate dropdown options
local usb_devices = get_usb_devices()
for busid, display_name in pairs(usb_devices) do
    devices:value(busid, display_name)
end

return m