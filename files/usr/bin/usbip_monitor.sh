#!/bin/ash

# USBIP Monitor Script for OpenWrt
# Compatible with ash and init.d

# 命令路径定义
USBIP_CMD="/usr/sbin/usbip"
USBIPD_CMD="/usr/sbin/usbipd"
KILLALL_CMD="/usr/bin/killall"
UCI_CMD="/sbin/uci"
LOGGER_CMD="/usr/bin/logger"
SLEEP_CMD="/bin/sleep"
BASENAME_CMD="/usr/bin/basename"
LS_CMD="/bin/ls"
GREP_CMD="/bin/grep"
AWK_CMD="/usr/bin/awk"
SORT_CMD="/usr/bin/sort"
COMM_CMD="/usr/bin/comm"
CAT_CMD="/bin/cat"
TEST_CMD="/bin/test"
ECHO_CMD="/bin/echo"

# 防抖配置
LAST_DEVICE_HASH=""
LAST_BOUND_HASH=""
FAILED_BIND_ATTEMPTS=""
LAST_CONFIG_HASH=""
LOG_COUNTER=0
MAX_LOG_BURST=3
LOG_BURST_WINDOW=30  # 30秒内最多输出3次详细日志

# 日志函数
log() {
    local level="$1"
    local message="$2"
    $LOGGER_CMD -p "user.$level" -t "usbip_monitor" "$message"
}

log_info() {
    log "info" "$1"
}

log_warn() {
    log "warn" "$1"
}

log_error() {
    log "err" "$1"
}

log_debug() {
    # 防抖：限制调试日志频率
    local current_time=$(date +%s)
    if [ -z "$LAST_DEBUG_TIME" ]; then
        LAST_DEBUG_TIME=$current_time
    fi
    
    local time_diff=$((current_time - LAST_DEBUG_TIME))
    if [ $time_diff -ge 10 ] || [ "$FORCE_DEBUG" = "1" ]; then
        log "debug" "$1"
        LAST_DEBUG_TIME=$current_time
        FORCE_DEBUG="0"
    fi
}

log_fatal() {
    log "err" "FATAL: $1"
    exit 1
}

# 计算字符串的简单哈希（用于防抖比较）
calculate_hash() {
    $ECHO_CMD "$1" | $AWK_CMD '{print length($0) ":" $0}' | md5sum | $AWK_CMD '{print $1}'
}

# 检查是否可以输出详细日志（防抖）
can_log_detailed() {
    local current_time=$(date +%s)
    
    if [ -z "$LAST_DETAILED_LOG_TIME" ]; then
        LAST_DETAILED_LOG_TIME=$current_time
        LOG_COUNTER=1
        return 0
    fi
    
    local time_diff=$((current_time - LAST_DETAILED_LOG_TIME))
    
    if [ $time_diff -ge $LOG_BURST_WINDOW ]; then
        # 时间窗口重置
        LAST_DETAILED_LOG_TIME=$current_time
        LOG_COUNTER=1
        return 0
    elif [ $LOG_COUNTER -lt $MAX_LOG_BURST ]; then
        LOG_COUNTER=$((LOG_COUNTER + 1))
        return 0
    else
        return 1
    fi
}

# 读取配置
read_config() {
    local enabled=$($UCI_CMD -q get usbip_server.config.enabled)
    local registration_mode=$($UCI_CMD -q get usbip_server.config.registration_mode)
    local server_port=$($UCI_CMD -q get usbip_server.config.server_port)
    local auto_bind=$($UCI_CMD -q get usbip_server.config.auto_bind)
    local device_list=$($UCI_CMD -q get usbip_server.config.device_list)
    
    CONFIG_ENABLED="${enabled:-0}"
    CONFIG_REGISTRATION_MODE="${registration_mode:-whitelist}"
    CONFIG_SERVER_PORT="${server_port:-3240}"
    CONFIG_AUTO_BIND="${auto_bind:-0}"
    CONFIG_DEVICE_LIST="${device_list:-}"
    
    # 检查配置是否变化
    local current_config="$CONFIG_ENABLED:$CONFIG_REGISTRATION_MODE:$CONFIG_SERVER_PORT:$CONFIG_AUTO_BIND:$CONFIG_DEVICE_LIST"
    local config_hash=$(calculate_hash "$current_config")
    
    if [ "$config_hash" != "$LAST_CONFIG_HASH" ]; then
        log_info "Configuration changed: enabled=$CONFIG_ENABLED, mode=$CONFIG_REGISTRATION_MODE, port=$CONFIG_SERVER_PORT, auto_bind=$CONFIG_AUTO_BIND"
        LAST_CONFIG_HASH="$config_hash"
        FORCE_DEBUG="1"  # 强制输出一次调试日志
    fi
}

# 获取所有USB设备
get_all_usb_devices() {
    for device in /sys/bus/usb/devices/*; do
        local busid=$($BASENAME_CMD "$device")
        # 只匹配有效的busid格式 (数字-数字)
        if $ECHO_CMD "$busid" | $GREP_CMD -qE '^[0-9]+-[0-9]+(\.[0-9]+)*$'; then
            $ECHO_CMD "$busid"
        fi
    done | $SORT_CMD
}

# 获取已绑定的USB设备
get_bound_devices() {
    if [ -d "/sys/bus/usb/drivers/usbip-host" ]; then
        $LS_CMD /sys/bus/usb/drivers/usbip-host/ 2>/dev/null | $GREP_CMD -E '^[0-9]+-[0-9]+(\.[0-9]+)*$' | $SORT_CMD
    else
        $ECHO_CMD ""
    fi
}

# 检查设备是否在失败列表中
is_failed_bind_attempt() {
    local busid="$1"
    $ECHO_CMD "$FAILED_BIND_ATTEMPTS" | $GREP_CMD -q ":$busid:"
}

# 添加设备到失败列表
add_failed_bind_attempt() {
    local busid="$1"
    if ! is_failed_bind_attempt "$busid"; then
        FAILED_BIND_ATTEMPTS="${FAILED_BIND_ATTEMPTS}:${busid}:"
        log_debug "Added $busid to failed bind attempts list"
    fi
}

# 绑定设备
bind_device() {
    local busid="$1"
    
    # 检查是否最近绑定失败过
    if is_failed_bind_attempt "$busid"; then
        log_debug "Skipping recently failed bind attempt for $busid"
        return 1
    fi
    
    log_info "Binding device $busid"
    if $USBIP_CMD bind -b "$busid" >/dev/null 2>&1; then
        log_info "Successfully bound device $busid"
        return 0
    else
        # 只有在第一次失败或长时间未尝试时才记录错误
        if ! is_failed_bind_attempt "$busid"; then
            log_error "Failed to bind device $busid"
            add_failed_bind_attempt "$busid"
        else
            log_debug "Failed to bind device $busid (previously logged)"
        fi
        return 1
    fi
}

# 解绑设备
unbind_device() {
    local busid="$1"
    log_info "Unbinding device $busid"
    if $USBIP_CMD unbind -b "$busid" >/dev/null 2>&1; then
        log_info "Successfully unbound device $busid"
        return 0
    else
        log_error "Failed to unbind device $busid"
        return 1
    fi
}

# 应用绑定策略
apply_binding_policy() {
    local all_devices=$(get_all_usb_devices)
    local bound_devices=$(get_bound_devices)
    
    # 计算设备列表哈希用于防抖
    local current_device_hash=$(calculate_hash "$all_devices")
    local current_bound_hash=$(calculate_hash "$bound_devices")
    
    # 检查设备列表是否真正变化
    local devices_changed=0
    if [ "$current_device_hash" != "$LAST_DEVICE_HASH" ]; then
        devices_changed=1
        LAST_DEVICE_HASH="$current_device_hash"
    fi
    
    if [ "$current_bound_hash" != "$LAST_BOUND_HASH" ]; then
        devices_changed=1
        LAST_BOUND_HASH="$current_bound_hash"
    fi
    
    # 只有在设备变化或可以输出详细日志时才记录详细信息
    if [ $devices_changed -eq 1 ] && can_log_detailed; then
        log_debug "USB device change detected"
        log_debug "All USB devices: $all_devices"
        log_debug "Bound devices: $bound_devices"
    elif [ $devices_changed -eq 1 ]; then
        log_debug "USB device change detected (detailed logging throttled)"
    fi
    
    case "$CONFIG_REGISTRATION_MODE" in
        "all")
            if [ $devices_changed -eq 1 ]; then
                log_info "Applying 'all' registration mode"
            fi
            # 绑定所有设备
            for busid in $all_devices; do
                if ! $ECHO_CMD "$bound_devices" | $GREP_CMD -q "^$busid$"; then
                    bind_device "$busid"
                fi
            done
            ;;
            
        "whitelist")
            if [ $devices_changed -eq 1 ]; then
                log_info "Applying 'whitelist' registration mode"
            fi
            # 绑定白名单中的设备
            for busid in $CONFIG_DEVICE_LIST; do
                if $ECHO_CMD "$all_devices" | $GREP_CMD -q "^$busid$"; then
                    if ! $ECHO_CMD "$bound_devices" | $GREP_CMD -q "^$busid$"; then
                        bind_device "$busid"
                    fi
                else
                    if can_log_detailed; then
                        log_warn "Device $busid in whitelist not found"
                    fi
                fi
            done
            
            # 解绑不在白名单中的已绑定设备
            for busid in $bound_devices; do
                if ! $ECHO_CMD "$CONFIG_DEVICE_LIST" | $GREP_CMD -q "$busid"; then
                    unbind_device "$busid"
                fi
            done
            ;;
            
        "blacklist")
            if [ $devices_changed -eq 1 ]; then
                log_info "Applying 'blacklist' registration mode"
            fi
            # 绑定不在黑名单中的设备
            for busid in $all_devices; do
                if ! $ECHO_CMD "$CONFIG_DEVICE_LIST" | $GREP_CMD -q "$busid"; then
                    if ! $ECHO_CMD "$bound_devices" | $GREP_CMD -q "^$busid$"; then
                        bind_device "$busid"
                    fi
                fi
            done
            
            # 解绑在黑名单中的设备
            for busid in $bound_devices; do
                if $ECHO_CMD "$CONFIG_DEVICE_LIST" | $GREP_CMD -q "$busid"; then
                    unbind_device "$busid"
                fi
            done
            ;;
            
        *)
            log_error "Unknown registration mode: $CONFIG_REGISTRATION_MODE"
            return 1
            ;;
    esac
    
    return 0
}

# 启动USBIP守护进程
start_usbipd() {
    log_info "Starting usbipd server on port $CONFIG_SERVER_PORT"
    if $USBIPD_CMD -D -4 -6 -t "$CONFIG_SERVER_PORT" >/dev/null 2>&1; then
        log_info "usbipd server started successfully"
        return 0
    else
        log_error "Failed to start usbipd server"
        return 1
    fi
}

# 停止USBIP守护进程
stop_usbipd() {
    log_info "Stopping usbipd server"
    if $KILLALL_CMD usbipd >/dev/null 2>&1; then
        log_info "usbipd server stopped"
        return 0
    else
        log_warn "No usbipd process found or failed to stop"
        return 1
    fi
}

# 清理失败的绑定尝试记录（定期清理）
cleanup_failed_attempts() {
    local current_time=$(date +%s)
    
    if [ -z "$LAST_CLEANUP_TIME" ]; then
        LAST_CLEANUP_TIME=$current_time
        return
    fi
    
    local time_diff=$((current_time - LAST_CLEANUP_TIME))
    
    # 每5分钟清理一次失败记录
    if [ $time_diff -ge 300 ] && [ -n "$FAILED_BIND_ATTEMPTS" ]; then
        log_debug "Cleaning up failed bind attempts list"
        FAILED_BIND_ATTEMPTS=""
        LAST_CLEANUP_TIME=$current_time
    fi
}

# 监控USB设备变化
monitor_usb_devices() {
    local last_devices=$(get_all_usb_devices)
    local current_devices=""
    local changed=0
    
    # 初始化哈希值
    LAST_DEVICE_HASH=$(calculate_hash "$last_devices")
    LAST_BOUND_HASH=$(calculate_hash "$(get_bound_devices)")
    
    while true; do
        $SLEEP_CMD 5
        
        # 定期清理失败记录
        cleanup_failed_attempts
        
        # 重新读取配置，支持配置热更新
        read_config
        
        # 检查是否被禁用
        if [ "$CONFIG_ENABLED" = "0" ]; then
            log_info "USBIP service disabled, exiting monitor"
            stop_usbipd
            exit 0
        fi
        
        # 获取当前设备列表
        current_devices=$(get_all_usb_devices)
        
        # 检查设备变化
        if [ "$last_devices" != "$current_devices" ]; then
            changed=1
        fi
        
        # 如果设备变化或需要定期检查，重新应用绑定策略
        if [ "$changed" -eq 1 ] || [ "$CONFIG_AUTO_BIND" = "1" ]; then
            apply_binding_policy
            last_devices="$current_devices"
            changed=0
        fi
    done
}

# 主函数
main() {
    log_info "USBIP Monitor starting"
    
    # 读取初始配置
    read_config
    
    # 检查是否启用服务
    if [ "$CONFIG_ENABLED" = "0" ]; then
        log_info "USBIP service is disabled"
        stop_usbipd
        # 解绑所有设备
        for busid in $(get_bound_devices); do
            unbind_device "$busid"
        done
        exit 0
    fi
    
    # 启动usbipd服务器
    if ! start_usbipd; then
        log_fatal "Failed to start usbipd server"
    fi
    
    # 初始绑定设备
    log_info "Performing initial device binding"
    if ! apply_binding_policy; then
        log_error "Failed to apply initial binding policy"
    fi
    
    # 如果启用自动绑定，启动监控循环
    if [ "$CONFIG_AUTO_BIND" = "1" ]; then
        log_info "Starting USB device monitor"
        monitor_usb_devices
    else
        log_info "Auto-bind disabled, exiting after initial setup"
    fi
}

# 信号处理
trap 'log_info "Received signal, shutting down"; stop_usbipd; exit 0' TERM INT
trap 'log_info "Configuration reload requested"; read_config' HUP

# 运行主函数
main "$@"