我已经为您生成了完整的 `luci-app-usbip-server` 软件包：

## 软件包结构

```
luci-app-usbip-server/
├── Makefile
├── files
│   ├── etc
│   │   ├── config
│   │   │   └── usbip_server
│   │   └── init.d
│   │       └── usbip_monitor
│   ├── usr
│   │   ├── bin
│   │   │   └── usbip_monitor.sh
│   │   └── lib
│   │       └── lua
│   │           └── luci
│   │               ├── controller
│   │               │   └── usbip_server.lua
│   │               └── model
│   │                   └── cbi
│   │                       └── usbip_server.lua
│   └── www
│       └── luci-static
│           └── resources
│               └── view
│                   └── usbip_server
│                       └── status.htm
└── po
    └── zh_Hans
        └── usbip_server.po
```

## 1. 更新的主 Makefile

```makefile
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
```

## 2. 配置文件 (files/etc/config/usbip_server)

```bash
config usbip_server 'config'
    option enabled '0'
    option registration_mode 'all'
    option device_list ''
    option server_port '3240'
    option auto_bind '1'
```

## 3. 修复的监控脚本 (files/usr/bin/usbip_monitor.sh)

```bash
#!/bin/ash
# USBIP Device Monitor and Auto-Bind Script
# Monitors USB device plug/unplug events and automatically binds devices based on configuration

# Configuration
POLL_INTERVAL=3
MODULE_NAME="usbip_core"
KNOWN_DEVICES_FILE="/tmp/usbip_known_devices"
LOG_TAG="usbip-monitor"
SYSFS_USB_ROOT="/sys/bus/usb/devices"
CONFIG_FILE="/etc/config/usbip_server"

# Function to log messages to system log
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | logger -t "$LOG_TAG"
}

# Function to get configuration value
get_config() {
    local value=$(uci -q get $CONFIG_FILE.config.$1)
    echo "${value}"
}

# Function to check if device should be bound based on configuration
should_bind_device() {
    local busid="$1"
    local vendor_id="$2"
    local product_id="$3"
    
    local enabled=$(get_config "enabled")
    local mode=$(get_config "registration_mode")
    local device_list=$(get_config "device_list")
    
    # If service is disabled, don't bind anything
    if [ "$enabled" != "1" ]; then
        return 1
    fi
    
    case "$mode" in
        "all")
            return 0
            ;;
        "whitelist")
            if echo "$device_list" | grep -q "$busid"; then
                return 0
            else
                return 1
            fi
            ;;
        "blacklist")
            if echo "$device_list" | grep -q "$busid"; then
                return 1
            else
                return 0
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if kmod module is loaded
check_module_loaded() {
    if lsmod | grep -q "$MODULE_NAME"; then
        return 0
    else
        return 1
    fi
}

# Function to get USB device info via sysfs
get_device_info() {
    local device="$1"
    local device_path="$SYSFS_USB_ROOT/$device"
    
    # Check if it's a valid device directory
    if [ ! -d "$device_path" ]; then
        return 1
    fi
    
    # Skip if it's a hub device
    if [ -f "$device_path/bDeviceClass" ]; then
        local device_class=$(cat "$device_path/bDeviceClass" 2>/dev/null)
        if [ "$device_class" = "09" ]; then
            return 1  # Skip hub devices
        fi
    fi
    
    # Get vendor and product ID
    if [ -f "$device_path/idVendor" ] && [ -f "$device_path/idProduct" ]; then
        local vendor_id=$(cat "$device_path/idVendor" 2>/dev/null | tr 'a-f' 'A-F' | tr -d ' ')
        local product_id=$(cat "$device_path/idProduct" 2>/dev/null | tr 'a-f' 'A-F' | tr -d ' ')
        
        if [ -z "$vendor_id" ] || [ -z "$product_id" ]; then
            return 1
        fi
    else
        return 1
    fi
    
    # Get manufacturer and product names if available
    local manufacturer="unknown vendor"
    local product="unknown product"
    
    if [ -f "$device_path/manufacturer" ]; then
        manufacturer=$(cat "$device_path/manufacturer" 2>/dev/null | head -c 100 | tr -d '\n' | sed 's/[^a-zA-Z0-9 _-]//g')
        [ -z "$manufacturer" ] && manufacturer="unknown vendor"
    fi
    
    if [ -f "$device_path/product" ]; then
        product=$(cat "$device_path/product" 2>/dev/null | head -c 100 | tr -d '\n' | sed 's/[^a-zA-Z0-9 _-]//g')
        [ -z "$product" ] && product="unknown product"
    fi
    
    echo "$device:$vendor_id:$product_id:$manufacturer:$product"
    return 0
}

# Function to get current USB device list via sysfs
get_current_devices() {
    local devices=""
    
    for device in $(ls "$SYSFS_USB_ROOT" 2>/dev/null | grep -E '^[0-9]+-[0-9]+(\.[0-9]+)*$' | sort); do
        local device_info=$(get_device_info "$device")
        if [ -n "$device_info" ]; then
            if [ -z "$devices" ]; then
                devices="$device_info"
            else
                devices="$devices"$'\n'"$device_info"
            fi
        fi
    done
    
    echo "$devices"
}

# Function to extract busid from device info line
extract_busid() {
    echo "$1" | cut -d: -f1
}

# Function to bind a USB device
bind_device() {
    local busid="$1"
    local vendor_id="$2"
    local product_id="$3"
    local manufacturer="$4"
    local product="$5"
    
    log_message "Attempting to bind device: $busid ($vendor_id:$product_id) - $manufacturer : $product"
    
    # Check if device is already bound
    if [ -d "/sys/bus/usb/drivers/usbip-host/$busid" ]; then
        log_message "INFO: Device $busid is already bound to usbip-host driver"
        return 0
    fi
    
    # Try to bind the device
    BIND_OUTPUT=$(usbip bind -b "$busid" 2>&1)
    BIND_EXIT_CODE=$?
    
    if [ $BIND_EXIT_CODE -eq 0 ]; then
        log_message "SUCCESS: Device $busid ($vendor_id:$product_id) bound successfully"
        return 0
    else
        if echo "$BIND_OUTPUT" | grep -q "already bound"; then
            log_message "INFO: Device $busid is already bound"
            return 0
        elif echo "$BIND_OUTPUT" | grep -q "not found"; then
            log_message "WARNING: Device $busid not found - may have been disconnected"
            return 1
        else
            log_message "ERROR: Failed to bind device $busid - $BIND_OUTPUT"
            return 1
        fi
    fi
}

# Function to start USBIP server (replacement for original usbipd)
start_usbip_server() {
    local port=$(get_config "server_port")
    port=${port:-3240}
    
    log_message "Starting USBIP server on port $port"
    
    # Kill any existing usbipd processes (including the original one)
    killall usbipd 2>/dev/null
    sleep 1
    
    # Start usbipd daemon with our configuration
    usbipd -D -4 -t -p "$port"
    
    if [ $? -eq 0 ]; then
        log_message "USBIP server started successfully on port $port"
        return 0
    else
        log_message "ERROR: Failed to start USBIP server"
        return 1
    fi
}

# Function to stop USBIP server
stop_usbip_server() {
    log_message "Stopping USBIP server"
    killall usbipd 2>/dev/null
    log_message "USBIP server stopped"
}

# Function to handle device changes
handle_device_changes() {
    local known_devices="$1"
    local current_devices="$2"
    
    # Create temporary files for comparison
    local known_file="/tmp/usbip_known.$$"
    local current_file="/tmp/usbip_current.$$"
    
    echo "$known_devices" | sort > "$known_file"
    echo "$current_devices" | sort > "$current_file"
    
    # Find new devices (in current but not in known)
    local new_devices=$(comm -13 "$known_file" "$current_file" 2>/dev/null)
    
    # Find removed devices (in known but not in current)
    local removed_devices=$(comm -23 "$known_file" "$current_file" 2>/dev/null)
    
    # Clean up temp files
    rm -f "$known_file" "$current_file"
    
    # Handle new devices
    if [ -n "$new_devices" ]; then
        log_message "New USB device(s) detected"
        echo "$new_devices" | while IFS= read -r device_info; do
            if [ -n "$device_info" ]; then
                local busid=$(extract_busid "$device_info")
                local vendor_id=$(echo "$device_info" | cut -d: -f2)
                local product_id=$(echo "$device_info" | cut -d: -f3)
                local manufacturer=$(echo "$device_info" | cut -d: -f4)
                local product=$(echo "$device_info" | cut -d: -f5)
                
                if should_bind_device "$busid" "$vendor_id" "$product_id"; then
                    log_message "Auto-binding new device: $busid ($vendor_id:$product_id)"
                    bind_device "$busid" "$vendor_id" "$product_id" "$manufacturer" "$product"
                else
                    log_message "Skipping device $busid based on configuration"
                fi
            fi
        done
    fi
    
    # Handle removed devices
    if [ -n "$removed_devices" ]; then
        log_message "USB device(s) removed"
        echo "$removed_devices" | while IFS= read -r device_info; do
            if [ -n "$device_info" ]; then
                local busid=$(extract_busid "$device_info")
                log_message "Device removed: $busid"
            fi
        done
    fi
    
    # Return if there were any changes
    if [ -n "$new_devices" ] || [ -n "$removed_devices" ]; then
        return 0
    else
        return 1
    fi
}

# Function to initialize and bind existing devices
initialize_devices() {
    log_message "Initializing USB device monitoring via sysfs"
    
    # Get current devices and save as known devices
    local current_devices=$(get_current_devices)
    echo "$current_devices" > "$KNOWN_DEVICES_FILE"
    
    # Bind all existing devices based on configuration
    if [ -n "$current_devices" ]; then
        log_message "Binding existing USB devices based on configuration"
        echo "$current_devices" | while IFS= read -r device_info; do
            if [ -n "$device_info" ]; then
                local busid=$(extract_busid "$device_info")
                local vendor_id=$(echo "$device_info" | cut -d: -f2)
                local product_id=$(echo "$device_info" | cut -d: -f3)
                local manufacturer=$(echo "$device_info" | cut -d: -f4)
                local product=$(echo "$device_info" | cut -d: -f5)
                
                if should_bind_device "$busid" "$vendor_id" "$product_id"; then
                    bind_device "$busid" "$vendor_id" "$product_id" "$manufacturer" "$product"
                fi
            fi
        done
    else
        log_message "No USB devices found during initialization"
    fi
}

# Main monitoring function
monitor_loop() {
    log_message "Starting USB device monitoring loop (interval: ${POLL_INTERVAL}s)"
    
    # Load initial known devices
    local known_devices=$(cat "$KNOWN_DEVICES_FILE" 2>/dev/null)
    
    while true; do
        # Check if service is enabled
        local enabled=$(get_config "enabled")
        
        if [ "$enabled" = "1" ]; then
            # Check if module is still loaded
            if ! check_module_loaded; then
                log_message "WARNING: $MODULE_NAME module not loaded"
                sleep "$POLL_INTERVAL"
                continue
            fi
            
            # Get current device list via sysfs
            local current_devices=$(get_current_devices)
            
            if [ -n "$current_devices" ]; then
                # Handle device changes
                if handle_device_changes "$known_devices" "$current_devices"; then
                    # Update known devices if there were changes
                    echo "$current_devices" > "$KNOWN_DEVICES_FILE"
                    known_devices="$current_devices"
                fi
            else
                # No devices found
                if [ -n "$known_devices" ]; then
                    echo "" > "$KNOWN_DEVICES_FILE"
                    known_devices=""
                    log_message "All USB devices removed"
                fi
            fi
        else
            # Service is disabled, clear known devices and stop server
            if [ -n "$known_devices" ]; then
                echo "" > "$KNOWN_DEVICES_FILE"
                known_devices=""
                stop_usbip_server
            fi
        fi
        
        # Wait before next check
        sleep "$POLL_INTERVAL"
    done
}

# Signal handler for clean shutdown
cleanup() {
    log_message "USBIP monitor script shutting down"
    rm -f /tmp/usbip_known.* /tmp/usbip_current.* 2>/dev/null
    exit 0
}

# Main execution
main() {
    log_message "Starting USBIP Device Monitor and Auto-Bind Script"
    
    # Set up signal handlers
    trap cleanup TERM INT
    
    # Wait for module to load initially
    log_message "Waiting for $MODULE_NAME kernel module to load"
    
    local max_wait=30
    local wait_count=0
    
    while [ $wait_count -lt $max_wait ]; do
        if check_module_loaded; then
            log_message "$MODULE_NAME module successfully loaded"
            break
        fi
        wait_count=$((wait_count + 1))
        sleep 1
    done
    
    if [ $wait_count -eq $max_wait ]; then
        log_message "ERROR: $MODULE_NAME module failed to load within $max_wait seconds"
        exit 1
    fi
    
    # Initialize and bind existing devices
    initialize_devices
    
    # Start monitoring loop
    monitor_loop
}

# Run main function
main
```

## 4. 修复的Init脚本 (files/etc/init.d/usbip_monitor)

```bash
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
NAME=usbip_monitor
DAEMON=/usr/bin/usbip_monitor.sh
PIDFILE=/var/run/usbip_monitor.pid

start_service() {
    # Disable the original usbipd service to avoid conflicts
    if [ -f /etc/init.d/usbipd ]; then
        /etc/init.d/usbipd disable 2>/dev/null
        /etc/init.d/usbipd stop 2>/dev/null
    fi
    
    procd_open_instance
    procd_set_param command "$DAEMON"
    procd_set_param respawn
    procd_set_param respawn_retry 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile "$PIDFILE"
    procd_close_instance
    
    # Start usbipd server if enabled in configuration
    if [ "$(uci -q get usbip_server.config.enabled)" = "1" ]; then
        local port=$(uci -q get usbip_server.config.server_port)
        /usr/sbin/usbipd -D -4 -t -p "${port:-3240}" &
    fi
}

stop_service() {
    # Stop our monitor and usbipd server
    killall usbip_monitor.sh 2>/dev/null
    killall usbipd 2>/dev/null
}

restart() {
    stop
    sleep 2
    start
}

service_triggers() {
    procd_add_reload_trigger usbip_server
}
```

## 5. 多语言LuCI控制器 (files/usr/lib/lua/luci/controller/usbip_server.lua)

```lua
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
```

## 6. 多语言CBI界面 (files/usr/lib/lua/luci/model/cbi/usbip_server.lua)

```lua
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
```

## 7. 中文语言包 (po/zh_Hans/usbip_server.po)

```po
msgid "USBIP Server"
msgstr "USBIP 服务端"

msgid "USBIP Server Configuration"
msgstr "USBIP 服务端配置"

msgid "Share your OpenWRT USB devices over TCP/IP network. Install <a href=\"https://github.com/vadimgrn/usbip-win2\" target=\"_blank\">usbip-win2</a> client software on your Windows computers. This package is generated with DeepSeek AI technology."
msgstr "通过 TCP/IP 网络共享您的 OpenWRT USB 设备。请在您的 Windows 电脑上安装 <a href=\"https://github.com/vadimgrn/usbip-win2\" target=\"_blank\">usbip-win2</a> 客户端软件。本软件包通过 DeepSeek AI 技术生成。"

msgid "Server Settings"
msgstr "服务器设置"

msgid "Enable USBIP Server"
msgstr "启用 USBIP 服务端"

msgid "Enable USBIP server and device monitoring"
msgstr "启用 USBIP 服务器和设备监控"

msgid "Server Port"
msgstr "服务器端口"

msgid "TCP port for USBIP server (default: 3240)"
msgstr "USBIP 服务器的 TCP 端口（默认：3240）"

msgid "Device Registration"
msgstr "设备注册"

msgid "Control which USB devices are automatically shared"
msgstr "控制哪些 USB 设备自动共享"

msgid "All Devices"
msgstr "全部设备"

msgid "Specific Devices (Whitelist)"
msgstr "指定设备（白名单）"

msgid "All Except Specific Devices (Blacklist)"
msgstr "除指定设备外（黑名单）"

msgid "USB Devices"
msgstr "USB 设备列表"

msgid "Select USB devices to include/exclude based on registration mode above"
msgstr "根据上述注册模式选择要包含/排除的 USB 设备"

msgid "unknown vendor"
msgstr "未知厂商"

msgid "unknown product"
msgstr "未知产品"
```

## 8. 状态页面模板 (files/www/luci-static/resources/view/usbip_server/status.htm)

```html
<script type="text/javascript">
// USBIP Server Status Page
(function() {
    'use strict';
    
    var updateStatus = function() {
        Promise.all([
            fetch('<%=luci.dispatcher.build_url("admin/services/usbip_server/status")%>').then(function(r) { return r.json(); }),
            fetch('<%=luci.dispatcher.build_url("admin/services/usbip_server/devices")%>').then(function(r) { return r.json(); })
        ]).then(function(data) {
            var status = data[0];
            var devices = data[1];
            
            // Update status indicators
            document.getElementById('monitor-status').className = status.monitor_running ? 'status-running' : 'status-stopped';
            document.getElementById('monitor-status').textContent = status.monitor_running ? 
                '<%=luci.i18n.translate("Running")%>' : '<%=luci.i18n.translate("Stopped")%>';
            
            document.getElementById('server-status').className = status.server_running ? 'status-running' : 'status-stopped';
            document.getElementById('server-status').textContent = status.server_running ? 
                '<%=luci.i18n.translate("Running")%>' : '<%=luci.i18n.translate("Stopped")%>';
            
            document.getElementById('module-status').className = status.modules_loaded ? 'status-running' : 'status-stopped';
            document.getElementById('module-status').textContent = status.modules_loaded ? 
                '<%=luci.i18n.translate("Loaded")%>' : '<%=luci.i18n.translate("Not Loaded")%>';
            
            // Update device list for selection
            var deviceSelect = document.getElementById('device-select');
            if (deviceSelect) {
                deviceSelect.innerHTML = '';
                devices.forEach(function(device) {
                    var option = document.createElement('option');
                    option.value = device.busid;
                    option.textContent = device.busid + ' - ' + device.vendor + ' : ' + device.product + ' (' + device.vid_pid + ')';
                    option.selected = device.bound;
                    deviceSelect.appendChild(option);
                });
            }
            
            // Update bound devices table
            var boundDevices = devices.filter(function(d) { return d.bound; });
            var boundTable = document.getElementById('bound-devices');
            if (boundTable) {
                boundTable.innerHTML = '';
                boundDevices.forEach(function(device) {
                    var row = document.createElement('tr');
                    row.innerHTML = '<td>' + device.busid + '</td>' +
                                   '<td>' + device.vid_pid + '</td>' +
                                   '<td>' + device.vendor + '</td>' +
                                   '<td>' + device.product + '</td>';
                    boundTable.appendChild(row);
                });
                
                if (boundDevices.length === 0) {
                    var row = document.createElement('tr');
                    row.innerHTML = '<td colspan="4" class="text-center"><%=luci.i18n.translate("No devices currently bound")%></td>';
                    boundTable.appendChild(row);
                }
            }
        }).catch(function(err) {
            console.error('Failed to update status:', err);
        });
    };
    
    // Initial update
    updateStatus();
    
    // Update every 5 seconds
    setInterval(updateStatus, 5000);
    
    // Add custom CSS
    var style = document.createElement('style');
    style.textContent = [
        '.status-running { color: #00cc00; font-weight: bold; }',
        '.status-stopped { color: #cc0000; font-weight: bold; }',
        '#device-select { width: 100%; min-height: 150px; }',
        '.device-table { width: 100%; border-collapse: collapse; }',
        '.device-table th, .device-table td { border: 1px solid #ddd; padding: 8px; text-align: left; }',
        '.device-table th { background-color: #f2f2f2; }',
        '.text-center { text-align: center; }'
    ].join('\n');
    document.head.appendChild(style);
})();
</script>

<div class="cbi-section">
    <h3><%=luci.i18n.translate("USBIP Server Status")%></h3>
    <div class="table">
        <div class="tr">
            <div class="td left" width="33%"><strong><%=luci.i18n.translate("Monitor Service")%>:</strong></div>
            <div class="td left"><span id="monitor-status"><%=luci.i18n.translate("Checking...")%></span></div>
        </div>
        <div class="tr">
            <div class="td left" width="33%"><strong><%=luci.i18n.translate("USBIP Server")%>:</strong></div>
            <div class="td left"><span id="server-status"><%=luci.i18n.translate("Checking...")%></span></div>
        </div>
        <div class="tr">
            <div class="td left" width="33%"><strong><%=luci.i18n.translate("Kernel Modules")%>:</strong></div>
            <div class="td left"><span id="module-status"><%=luci.i18n.translate("Checking...")%></span></div>
        </div>
    </div>
</div>

<div class="cbi-section">
    <h3><%=luci.i18n.translate("Available USB Devices")%></h3>
    <select multiple="multiple" id="device-select" class="cbi-input-select">
        <option value=""><%=luci.i18n.translate("Loading devices...")%></option>
    </select>
    <div class="cbi-value-description">
        <%=luci.i18n.translate("Hold Ctrl to select multiple devices. Selected devices will be used in whitelist/blacklist mode.")%>
    </div>
</div>

<div class="cbi-section">
    <h3><%=luci.i18n.translate("Currently Bound Devices")%></h3>
    <table class="device-table">
        <thead>
            <tr>
                <th><%=luci.i18n.translate("Bus ID")%></th>
                <th><%=luci.i18n.translate("VID:PID")%></th>
                <th><%=luci.i18n.translate("Vendor")%></th>
                <th><%=luci.i18n.translate("Product")%></th>
            </tr>
        </thead>
        <tbody id="bound-devices">
            <tr>
                <td colspan="4" class="text-center"><%=luci.i18n.translate("Loading...")%></td>
            </tr>
        </tbody>
    </table>
</div>
```

