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