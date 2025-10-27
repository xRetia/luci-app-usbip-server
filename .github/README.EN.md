# luci-app-usbip-server

[中文文档](README.md)

## Project Description

luci-app-usbip-server is a comprehensive OpenWRT LuCI application designed specifically for network sharing of USB devices. With this plugin, you can easily configure your OpenWRT device as a USBIP server, enabling network sharing of USB devices and allowing multiple client devices to remotely access and use USB devices connected to the server.

![Project Screenshot](.github/screenshot.png)

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

## System Requirements

- OpenWRT 19.07 or higher
- Kernel version 4.14 or higher
- At least 8MB available storage space
- USB controller and at least one USB device

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

## Advanced Features

### Intelligent Device Management
- **Real-time Monitoring Mechanism** - Monitors USB device hot-plug status through an event-driven approach
- **Device Information Collection** - Automatically retrieves and displays detailed device information (manufacturer, model, device ID, etc.)
- **Auto-binding Policy** - Automatically handles newly connected USB devices according to configured management policies

### Service Optimization
- **Resource Management** - Optimized for embedded devices to minimize CPU and memory usage
- **Conflict Detection** - Automatically detects and resolves potential conflicts with system services
- **Exception Recovery** - Automatic recovery capability when the service unexpectedly terminates
- **Logging** - Detailed operation and error logs for easy troubleshooting

## Configuration File Description

Main configuration file path:
```
/etc/config/usbip_server  # Main configuration file
```

Configuration items:
- `enabled` - Whether to enable the service (0=disabled, 1=enabled)
- `port` - USBIP server listening port (default: 3240)
- `device_mode` - Device registration mode (all=all devices, whitelist=whitelist, blacklist=blacklist)
- `devices` - Device list, used in whitelist/blacklist mode

## Performance and Security

### Performance Considerations
- It is recommended to use in environments with sufficient network bandwidth, especially when sharing large-capacity storage devices
- There may be latency for devices with high-frequency data transmission (such as cameras, audio devices)
- The monitoring service has extremely low resource consumption, typically less than 1% CPU and a few MB of memory

### Security Recommendations
- It is recommended to use this service in a trusted network environment
- Consider using a firewall to restrict access to the USBIP service port to specific IPs only
- Regularly update your OpenWRT system and this plugin to obtain security updates
- For sensitive devices, it is recommended to use whitelist mode to precisely control access permissions

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

## Development and Contribution

### Project Structure
```
luci-app-usbip-server/
├── Makefile                      # Build configuration
├── files/
│   ├── etc/
│   │   ├── config/               # Configuration file directory
│   │   └── init.d/               # Initialization scripts
│   ├── usr/
│   │   ├── bin/                  # Executable scripts
│   │   └── lib/lua/luci/         # LuCI modules
│   └── www/                      # Web resources
└── po/                           # Multi-language files
```

### Technology Stack
- **Frontend**: LuCI CBI Framework, JavaScript, HTML/CSS
- **Backend**: Lua, Shell Script
- **System**: OpenWRT, Linux USB Subsystem

### Contribution Guidelines
We welcome community contributions, including but not limited to:
- Submitting bug reports and feature suggestions
- Improving code and documentation
- Adding new language support
- Optimizing performance and security

Please participate in project development through GitHub Issues and Pull Requests.

### Development Environment Setup
1. Set up the build environment according to OpenWRT official documentation
2. Add this project to the OpenWRT package directory
3. Use OpenWRT SDK for development and testing

## License

MIT License

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied. Users assume all risks associated with its use.

## Acknowledgments

Thanks to all developers and community members who have contributed to the development of USBIP technology.

---

**Note**: Before using this software, ensure you understand the security implications of the USBIP protocol, especially when sharing USB devices over a network.