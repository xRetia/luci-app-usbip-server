module("luci.controller.usbip_server", package.seeall)

function index()
    local i18n = luci.i18n.translate
    
    entry({"admin", "services", "usbip_server"}, cbi("usbip_server"), i18n("USBIP Server"), 60).dependent = true
    entry({"admin", "services", "usbip_server", "status"}, call("action_status")).leaf = true
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