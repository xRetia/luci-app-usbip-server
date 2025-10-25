module("luci.controller.usbip_server", package.seeall)

function index()
    local i18n = luci.i18n.translate
    
    entry({"admin", "services", "usbip_server"}, cbi("usbip_server"), i18n("USBIP Server"), 60).dependent = true
    entry({"admin", "services", "usbip_server", "status"}, call("action_status")).leaf = true
    entry({"admin", "services", "usbip_server", "devices"}, call("action_devices")).leaf = true
end

function action_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local status = {
        monitor_running = (sys.process.info("usbip_monitor.sh") ~= nil),
        server_running = (sys.process.info("usbipd") ~= nil),
        modules_loaded = (sys.exec("lsmod | grep -q usbip_core && echo loaded || echo not_loaded") == "loaded\n")
    }
    
    http.prepare_content("application/json")
    http.write_json(status)
end

function action_devices()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local i18n = luci.i18n.translate
    
    local devices = {}
    local bound_devices = sys.exec("usbip list -l 2>/dev/null")
    
    -- Parse bound devices
    for busid, vid_pid, vendor, product in bound_devices:gmatch(".-busid ([^%s]+) %(([^%)]+)%)%s*([^:]+) : ([^\n]+)") do
        table.insert(devices, {
            busid = busid,
            vid_pid = vid_pid,
            vendor = vendor:gsub("^%s*(.-)%s*$", "%1"),
            product = product:gsub("^%s*(.-)%s*$", "%1"),
            bound = true
        })
    end
    
    -- Get all USB devices from sysfs
    local sysfs_devices = sys.exec("ls /sys/bus/usb/devices/ 2>/dev/null | grep -E '^[0-9]+-[0-9]+(\\.[0-9]+)*$'")
    for device in sysfs_devices:gmatch("[^\n]+") do
        local found = false
        for _, dev in ipairs(devices) do
            if dev.busid == device then
                found = true
                break
            end
        end
        
        if not found then
            local vendor = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idVendor 2>/dev/null", device)) or "unknown"
            local product = sys.exec(string.format("cat /sys/bus/usb/devices/%s/idProduct 2>/dev/null", device)) or "unknown"
            local manufacturer = sys.exec(string.format("cat /sys/bus/usb/devices/%s/manufacturer 2>/dev/null", device)) or i18n("unknown vendor")
            local product_name = sys.exec(string.format("cat /sys/bus/usb/devices/%s/product 2>/dev/null", device)) or i18n("unknown product")
            
            table.insert(devices, {
                busid = device,
                vid_pid = string.format("%s:%s", vendor:gsub("%s+", ""), product:gsub("%s+", "")),
                vendor = manufacturer:gsub("^%s*(.-)%s*$", "%1"),
                product = product_name:gsub("^%s*(.-)%s*$", "%1"),
                bound = false
            })
        end
    end
    
    http.prepare_content("application/json")
    http.write_json(devices)
end