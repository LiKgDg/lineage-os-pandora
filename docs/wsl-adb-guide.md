# WSL 环境下使用 adb 的完整指南

整理日期：2026-10-30
适用：Windows 11 + WSL 2（Ubuntu），需从 WSL 内操作 Android 设备

---

## 一、三条路线对比

WSL 是运行在 Windows 上的轻量虚拟机，**默认看不到宿主机的 USB 硬件**。所以"在 WSL 里装 adb"只解决了一半问题，真正的工作量在打通设备可见性。

| 方案 | 原理 | 稳定性 | 配置量 | 适用场景 |
|---|---|---|---|---|
| **A. 复用 Windows 的 adb server**（推荐） | Windows 跑 adb server 监听 5037，WSL 的 adb 客户端通过 `ADB_SERVER_SOCKET` 连过去 | 高 | 小 | 日常调试、脚本自动化、刷机 |
| **B. usbipd-win 直通 USB** | 用 USB/IP 把设备从 Windows 挂到 WSL，WSL 认为设备是本地 USB | 中 | 大 | 需要 `fastboot`、`lsusb`、直接读写 USB 的场景 |
| **C. 无线调试** | 设备开 `adb tcpip`，WSL 直接 `adb connect <手机IP>:5555` | 中 | 最小 | 设备不在手边、免插线 |

**结论**：只要能接受"设备由 Windows 侧持有"，方案 A 最省事；需要 `fastboot` 或原生 USB 访问时用方案 B。

---

## 二、方案 A：复用 Windows 的 adb server

### 2.1 Windows 端：让 adb server 对外监听

默认 `adb` 只监听 `127.0.0.1:5037`，WSL 访问不到。必须加 `-a`（all interfaces）：

```powershell
adb kill-server
adb -a -P 5037 nodaemon server
```

或者后台常驻：

```powershell
adb kill-server
adb -a nodaemon server start
```

**防火墙**：放行 5037 入站，否则 WSL 连接会被拦：

```powershell
New-NetFirewallRule -DisplayName "adb 5037" -Direction Inbound -Protocol TCP -LocalPort 5037 -Action Allow
```

### 2.2 WSL 端：安装 adb 并指向 Windows

```bash
sudo apt update
sudo apt install -y adb android-sdk-platform-tools-common
```

获取 Windows 宿主机 IP，分两种情况：

**情况 1：`networkingMode=Mirrored`（本机就是这种）**

WSL 与 Windows 共享网络栈，直接走回环地址即可，不需要算 IP：

```bash
echo 'export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037' >> ~/.bashrc
source ~/.bashrc
```

判断方法：`cat /etc/wsl.conf` 或 `%UserProfile%\.wslconfig` 里有 `networkingMode=Mirrored`。
本机实测默认路由是 `default via 192.168.31.1`（LAN 网关，而非 WSL 虚拟网段），即为镜像模式。

**情况 2：默认 NAT 模式**

WSL 2 的默认网关就是宿主机：

```bash
echo "export ADB_SERVER_SOCKET=tcp:$(ip route show default | awk '{print $3}'):5037" >> ~/.bashrc
source ~/.bashrc
```

验证：

```bash
adb devices
# 期望输出
# List of devices attached
# <serial>	device
```

### 2.3 关键细节

- **`ADB_SERVER_SOCKET` 必须在任何 adb 命令之前设置**。一旦 WSL 本地 adb 已经起了 server，它会占住 5037，之后设环境变量也没用，必须先 `adb kill-server`。
- **IP 会漂移**。WSL 2 每次重启后网段可能变化，所以用 `ip route` 动态取，不要写死。
- **WSL 2.0+ 的镜像网络模式**（`networkingMode=Mirrored`，写在 `%UserProfile%\.wslconfig`）下，WSL 与 Windows 共享网络栈，可以直接 `export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037`，不必再算 IP。**本机即为此模式。**
- **版本要对齐**。Windows 和 WSL 两侧 adb 版本差太多会报 `adb server version doesn't match this client`。要么两边都用平台工具同版本，要么让 WSL 只用客户端、server 全交给 Windows（方案 A 天然如此）。

---

## 三、方案 B：usbipd-win 直通 USB

适合需要 `fastboot`、`lsusb` 或设备在 WSL 内以 `/dev/bus/usb/...` 出现的场景。

### 3.1 前置条件

- Windows 11（内部版本 22000+），x64 或 ARM64
- WSL 2，Linux 内核 **≥ 5.10.60.1**（低于此版本先 `wsl --update`）
- 管理员权限（`bind` 需要）

### 3.2 安装

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

或从 [usbipd-win releases](https://github.com/dorssel/usbipd-win/releases) 下载 `.msi`。

安装后会得到：`usbipd` 服务、`usbipd` 命令行工具、一条同名防火墙规则。

### 3.3 挂载设备

```powershell
# 1. 列出设备，记下 BUSID（如 2-2）
usbipd list

# 2. 共享设备（需管理员）
usbipd bind --busid 2-2

# 3. 附加到 WSL（WSL 终端保持打开，否则 VM 会休眠）
usbipd attach --wsl --busid 2-2
```

WSL 内验证：

```bash
lsusb
adb devices
```

用完释放：

```powershell
usbipd detach --busid 2-2
```

### 3.4 注意事项

- 设备附加到 WSL 后，**Windows 侧就不再能访问它**（包括 Windows 的 adb、小米刷机工具）。
- `bind` 一次即可，之后每次 `attach` 不需要管理员。
- 非 root 用户需要 udev 规则才能访问设备节点。
- WSL 关机或重启后需要重新 `attach`。

---

## 四、方案 C：无线调试

```bash
# 先用 USB 连一次并授权
adb tcpip 5555
adb connect <手机IP>:5555
adb devices
```

WSL 走方案 A 时，`adb connect` 是发给 Windows 的 server，实际连接由 Windows 发起，所以手机与 **Windows** 要在同一网段。

---

## 五、常见报错与排查

| 现象 | 原因 | 处理 |
|---|---|---|
| WSL 里 `adb devices` 空列表，Windows 里正常 | WSL 自己起了 adb server，占住 5037 | `adb kill-server`，确认 `ADB_SERVER_SOCKET` 已设后再执行 |
| `adb server version doesn't match this client` | 两侧 adb 版本不一致 | 统一 platform-tools 版本，或只用 Windows 的 server |
| `cannot connect to daemon` / `Connection refused` | Windows 端没加 `-a`，或防火墙拦截 | 重启 server 加 `-a`，放行 5037 |
| `ADB server didn't ACK` | 5037 被其它进程占用 | `netstat -ano \| findstr 5037` 找到 PID 后结束 |
| `error: no devices/emulators found` 但设备已插 | 设备未授权 / 驱动异常 / 挂在了 WSL 侧 | 手机确认"允许 USB 调试"，`adb kill-server` 后重插 |
| `usbipd bind` 报权限错误 | 未用管理员 PowerShell | 以管理员身份重开 PowerShell |
| `usbipd attach` 后设备在 WSL 里时有时无 | WSL VM 休眠导致 USB/IP 断链 | 保持 WSL 终端打开，或重跑 `attach` |
| WSL 重启后 adb 又连不上 | 宿主 IP 变了 | 用 `ip route` 动态取 IP，别写死 |

排查顺序建议：**Windows 端 `adb devices` 是否正常 → 5037 是否监听在 0.0.0.0 → 防火墙 → WSL 端 `ADB_SERVER_SOCKET` → WSL 是否残留本地 server**。

---

## 六、本项目的实际情况

当前项目（Xiaomi 17 Pro / pandora 移植）**没有在 WSL 内装 adb**，而是直接调用 Windows 侧的 `platform-tools/adb.exe` 与小米刷机包里的 `fastboot.exe`：

```
platform-tools/adb.exe devices
"F:/.../bin/windows/fastboot.exe" flash super sysonly/super.img
```

这样做的原因：
- 刷机需要 `fastboot`，而 `fastboot` 必须由 Windows 侧持有 USB 设备（方案 B 才能搬进 WSL）；
- WSL 只承担编译，不参与设备通信，避免两套 adb server 打架。

如果后续要在 WSL 内跑自动化脚本（例如批量 `adb shell` 校验），按方案 A 配置即可，Windows 侧 `adb.exe` 与 WSL 侧可以共存，共用同一个 server。
