你好，我是一个只会使用 OpenWRT 的用户，我想让你把这些东西打包成 luci-app-usbip-server 软件包。

软件包依赖：
usbip、usbip-server、usbip-client、kmod-usbip、kmod-usbip-client、kmod-usbip-server 这几个包；

LuCI 设计要求：
1. 提供一个 LuCI 界面，注册在 LuCI 服务（services）菜单下；
2. 菜单名字 “USBIP 服务端”（内部名称：usbip_server）；
3. LuCI 界面提供：标题、说明、USBIP服务端运行状态、配置参数

luci-app-usbip-server 界面内容：
1. 标题：USBIP 服务端配置;
2. 说明：将您的 OpenWRT 作为 USB 共享器，通过 TCP/IP 协议在多台电脑上共享您的 USB 设备。请在您的 Windows 电脑上安装 https://github.com/vadimgrn/usbip-win2 客户端软件，本软件包通过 DeepSeek AI 技术生成。；
3. 提供“启用”复选框选项：勾选表示 Enable usbipd、usbip_monitor 服务，并立即 Start;
4. 提供“注册设备”下拉列表：全部设备、指定设备（白名单）、除指定设备外（黑名单）；
5. 提供“USB设备列表”多选列表，当“注册设备”为指定设备（白名单）、除指定设备外（黑名单），允许勾选USB设备；
以上所有操作需要配合 usbip_monitor.sh 执行

请你帮我生成一个完整的 luci-app-usbip-server 软件包，包含 usbip_monitor。