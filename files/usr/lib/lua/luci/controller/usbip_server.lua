module("luci.controller.usbip_server", package.seeall)

function index()
    local i18n = luci.i18n.translate
    
    entry({"admin", "services", "usbip_server"}, cbi("usbip_server"), i18n("USBIP Server"), 60).dependent = true
    entry({"admin", "services", "usbip_server", "status"}, call("action_status")).leaf = true
end

function action_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    
    -- 初始化状态信息
    local status = {
        monitor_running = (sys.exec("pgrep -f usbip_monitor.sh >/dev/null && echo running || echo stopped") == "running\n"),
        server_running = (sys.exec("pgrep -f usbipd >/dev/null && echo running || echo stopped") == "running\n"),
        modules_loaded = (sys.exec("lsmod | grep -q usbip_core && echo loaded || echo not_loaded") == "loaded\n"),
        bound_devices = {}
    }
    
    -- 查找绑定的设备
    local usb_devices_dir = "/sys/bus/usb/devices/"
    if fs.access(usb_devices_dir) then
        local devices = fs.dir(usb_devices_dir)
        if devices then
            for busid in devices do
                -- 跳过非USB设备和子设备
                if busid:match("^%d%-[%d%.]+") then
                    local uevent_path = usb_devices_dir .. busid .. "/uevent"
                    if fs.access(uevent_path) then
                        -- 读取uevent文件内容
                        local uevent_content = fs.readfile(uevent_path) or ""
                        
                        -- 检查是否绑定到usbip-host驱动
                        if uevent_content:find("DRIVER=usbip%-host") then
                            -- 尝试获取设备信息
                            local idVendor = ""
                            local idProduct = ""
                            local manufacturer = ""
                            local product = ""
                            
                            -- 读取idVendor和idProduct
                            local idVendor_path = usb_devices_dir .. busid .. "/idVendor"
                            local idProduct_path = usb_devices_dir .. busid .. "/idProduct"
                            if fs.access(idVendor_path) then
                                idVendor = fs.readfile(idVendor_path) or ""
                                idVendor = idVendor:gsub("\n", "")
                            end
                            if fs.access(idProduct_path) then
                                idProduct = fs.readfile(idProduct_path) or ""
                                idProduct = idProduct:gsub("\n", "")
                            end
                            
                            -- 尝试获取厂商和产品名称
                            local manufacturer_path = usb_devices_dir .. busid .. "/manufacturer"
                            local product_path = usb_devices_dir .. busid .. "/product"
                            if fs.access(manufacturer_path) then
                                manufacturer = fs.readfile(manufacturer_path) or ""
                                manufacturer = manufacturer:gsub("\n", "")
                            end
                            if fs.access(product_path) then
                                product = fs.readfile(product_path) or ""
                                product = product:gsub("\n", "")
                            end
                            
                            -- 添加到绑定设备列表
                            table.insert(status.bound_devices, {
                                busid = busid,
                                vid_pid = idVendor .. ":" .. idProduct,
                                vendor = manufacturer,
                                product = product
                            })
                        end
                    end
                end
            end
        end
    end
    
    http.prepare_content("application/json")
    http.write_json(status)
end