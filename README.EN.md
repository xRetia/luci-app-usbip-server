# luci-app-usbip-server

[中文文档](README.md)

## Project Description

luci-app-usbip-server is an OpenWRT LuCI application that allows you to use your OpenWRT device as a USBIP server to share USB devices over the network. This package is generated with DeepSeek AI technology.

## Features

- 🚀 **Complete USBIP Server Solution**
- 📱 **Intuitive Web Management Interface**
- 🔄 **Real-time Device Monitoring and Auto-binding**
- ⚡ **Low Resource Consumption via sysfs**
- 🌐 **Multi-language Support (English/Chinese)**
- 🎯 **Flexible Device Management Policies**
  - Share All Devices
  - Whitelist Mode (Share only selected devices)
  - Blacklist Mode (Share all except selected devices)

## Dependencies

- `usbip`
- `usbip-server`
- `usbip-client`
- `kmod-usbip`
- `kmod-usbip-client`
- `kmod-usbip-server`
- `lua`
- `luci-base`
- `luci-compat`

## Installation

### Compile from Source

1. Place the package in OpenWRT build system:
```bash
cp -r luci-app-usbip-server ~/openwrt/package/
```

2. Configure and compile:
```bash
make menuconfig
# Select luci-app-usbip-server in LuCI -> Applications
make package/luci-app-usbip-server/compile V=s
```

### Manual Installation

1. Install dependencies:
```bash
opkg update
opkg install usbip usbip-server usbip-client kmod-usbip kmod-usbip-client kmod-usbip-server
```

2. Install language package (for Chinese interface, optional):
```bash
opkg install luci-i18n-base-zh-cn
```

3. Install the package:
```bash
opkg install luci-app-usbip-server_1.0.1-1_all.ipk
```

## Usage

### Web Interface Management

1. Log in to LuCI administration interface
2. Navigate to **Services** → **USBIP Server**
3. Configure the following options:

**Basic Settings:**
- ✅ **Enable USBIP Server** - Enable/disable the entire service
- 🔢 **Server Port** - USBIP service listening port (default: 3240)

**Device Registration Mode:**
- 🌐 **All Devices** - Share all connected USB devices
- ✅ **Specific Devices (Whitelist)** - Share only selected devices
- ❌ **All Except Specific Devices (Blacklist)** - Share all devices except selected ones

**USB Device List:**
- In whitelist or blacklist mode, select devices to include or exclude from the list

### Client Connection

**Windows Client:**
1. Install [usbip-win2](https://github.com/vadimgrn/usbip-win2)
2. View available USB devices:
```cmd
usbip list -r <OpenWRT_Device_IP>
```
3. Connect device:
```cmd
usbip attach -r <OpenWRT_Device_IP> -b <device_busid>
```

**Linux Client:**
1. Load USBIP kernel modules:
```bash
modprobe usbip-core
modprobe vhci-hcd
```
2. View available devices:
```bash
usbip list -r <OpenWRT_Device_IP>
```
3. Connect device:
```bash
usbip attach -r <OpenWRT_Device_IP> -b <device_busid>
```

## Technical Features

### Smart Device Monitoring
- Real-time monitoring of USB device hot-plug events
- Device discovery via sysfs with minimal resource consumption
- Automatic binding of newly inserted devices

### Service Management
- Automatically disables system's original usbipd service to avoid conflicts
- Complete service lifecycle management
- System log integration

### System Requirements
- OpenWRT 19.07 or higher
- Kernel version 4.14 or higher
- At least 8MB available storage space

## Troubleshooting

### Common Issues

**1. Device Binding Fails**
- Check if kernel modules are properly loaded: `lsmod | grep usbip`
- Confirm USB devices are visible in the system: `lsusb` or check `/sys/bus/usb/devices/`

**2. Client Cannot Connect**
- Ensure firewall allows TCP connections on USBIP port (default 3240)
- Verify service is running: `ps | grep usbipd`

**3. Device List is Empty**
- Check if USB devices are properly connected
- Confirm USB controller drivers are loaded

### Log Viewing
```bash
# View monitor service logs
logread | grep usbip-monitor

# View system logs
logread
```

## File Structure

```
/etc/config/usbip_server          # Configuration file
/etc/init.d/usbip_monitor         # Init script
/usr/bin/usbip_monitor.sh         # Main monitor script
/usr/lib/lua/luci/controller/     # LuCI controller
/usr/lib/lua/luci/model/cbi/      # LuCI configuration interface
/www/luci-static/resources/view/  # Web interface resources
```

## Development Information

### Technology Stack
- **Frontend**: LuCI CBI Framework, JavaScript, HTML/CSS
- **Backend**: Lua, Shell Script
- **System**: OpenWRT, Linux USB Subsystem

### Contributing
Issues and Pull Requests are welcome to improve this project.

## License

MIT License

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied. Users assume all risks associated with its use.

---

**Note**: Before using this software, ensure you understand the security implications of the USBIP protocol, especially when sharing USB devices over a network.