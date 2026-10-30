# Xiaomi 17 Pro (pandora / canoe) — LineageOS 23.2 设备树

> **仓库**：https://github.com/LiKgDg/pandora-lineage
> **预编译镜像**：[Releases v0.1.0](https://github.com/LiKgDg/pandora-lineage/releases/tag/v0.1.0)
> —— `recovery.img` 104,857,600 B，md5 `a64ee7ccef50634dbb088fe21c0b5d6c`（真机验证通过）

为 **小米 17 Pro**（代号 `pandora`，平台 `canoe`，SoC SM8850）移植 LineageOS 23.2 的设备树，
目标是把 LOS 的 recovery 跑起来。

## 一、设备参数

| 项 | 值 |
|---|---|
| 代号 | `pandora` |
| 平台 | `canoe`（SM8850） |
| 机型号 | 25098PN5AC |
| 内核 | `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k`（预编译，39,963,136 B） |
| KMI | `android16-5` |
| Page size | 4 KB |
| 屏幕 | 1220 × 2656，density 520 |
| super | 12.5 GiB（`BOARD_SUPER_PARTITION_SIZE := 13421772800`） |
| 分区 | A/B + 独立 `init_boot` / `vendor_boot` / `recovery` |

## 二、来源

设备树的**基线**来自社区 TWRP 树 [`AzumaChiaki/device-xiaomi-pandora`](https://github.com/AzumaChiaki/device-xiaomi-pandora)
（分支 `fox_12.1-a14`），本仓库在其基础上做了 LineageOS 23.2（Android 16）适配。

预编译内核 / dtb / dtbo 来自上述仓库的 `prebuilt/`，即从小米官方固件提取的原厂文件。

> 如果你要分发本仓库，请同时保留上游的署名。原厂 blob（内核、dtb）版权归小米所有。

## 三、相对上游的改动

完整 diff 见 [`patches/0001-device-tree-los-adaptation.patch`](patches/0001-device-tree-los-adaptation.patch)。

| 文件 | 改动 | 原因 |
|---|---|---|
| `AndroidProducts.mk` | 指向 `lineage_pandora.mk` | 上游是 TWRP 的 `twrp_pandora.mk` |
| `lineage_pandora.mk` | **新增** | LOS 产品配置，继承 `core_64_bit` / `base` / `virtual_ab_ota` |
| `device.mk` | 去掉 `TW_*`，保留 bootctrl，补 recovery UI 属性 | LOS 不认 TWRP 变量 |
| `BoardConfig.mk` | 删 `PLATFORM_VERSION` 等只读赋值 | AOSP 里这些由 `version_defaults.mk` 定义，赋值会 fatal |
| `BoardConfig.mk` | 补 `BOARD_INIT_BOOT_HEADER_VERSION := 4` | 否则 soong 报 `header_version: must be set` |
| `BoardConfig.mk` | 屏幕改 1220×2656 / 520 | 上游写的是 1440×2560 / 560（别的机型） |
| `BoardConfig.mk` | 补 `TARGET_RECOVERY_DEVICE_DIRS` + UI margin | 让 recovery 打进 init/fstab 并留出边距 |
| `twrp_pandora.mk`、`vendorsetup.sh`、`build_local.sh`、`prepare_from_plg.sh` | **删除** | TWRP / OrangeFox 专属 |

## 四、环境要求

- Ubuntu 24.04（WSL2 可用），**源码树不能放在 `/mnt/c`**（大小写不敏感 + 跨文件系统极慢）
- 磁盘：源码 + out 约需 300 GB
- 内存：≥ 16 GB，建议配 32 GB swap
- 依赖：

```bash
sudo apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git git-lfs gnupg gperf imagemagick kmod lib32readline-dev lib32z1-dev libdw-dev \
  libelf-dev libgnutls28-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop \
  pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev unzip \
  cpio zstd device-tree-compiler erofs-utils protobuf-compiler python3-protobuf
```

- 同步源码：

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
repo sync -j8
```

## 五、构建

```bash
# 1. 把本仓库放到 device/xiaomi/pandora
cp -a device/xiaomi/pandora /path/to/lineage/device/xiaomi/

# 2. 编译 recovery
bash scripts/build-recovery.sh
```

`build-recovery.sh` 会做三件事，**每一件都对应一个真实踩过的坑**：

1. 禁用 `prebuilts/misc/protobuf_vendorcompat/Android.bp`
   —— 它与 `hardware/lineage/compat` 定义同名 5 个模块，共存会让 soong 报 `already defined`
2. `set +u` 后再 `source build/envsetup.sh`
   —— AOSP 的 `envsetup.sh:21` 直接引用 `$TOP`，在 `set -u` 下会中止，
      表现为「source 返回 0 但 lunch 未定义」
3. 用 `lunch lineage_pandora-bp4a-userdebug`
   —— release 名必须是三段式，`bp4a` 对应 Android 16 Q4

## 六、刷机

WSL 没有 USB 透传，**必须在 Windows 上刷**：

```bash
FASTBOOT=".../platform-tools/fastboot.exe" \
RECOVERY_IMG="//wsl.localhost/Ubuntu-24.04/root/android/lineage/out/target/product/pandora/recovery.img" \
bash scripts/flash-recovery.sh
```

或手动：

```bash
fastboot flash recovery recovery.img
fastboot reboot recovery
```

## 七、验证结果

### 7.1 真机验证（2026-10-29）

刷入 `recovery_a` 后重启，**16 秒进入 recovery**：

```
$ fastboot flash recovery_a recovery.img
Sending 'recovery_a' (102400 KB)   100.0%  39.32 MB/s
Writing 'recovery_a'               OKAY
Finished. Total time: 2.650s

$ fastboot reboot recovery
$ adb devices -l
fd3af370   recovery   product:lineage_pandora   model:25098PN5AC   device:pandora
```

`product:lineage_pandora` 说明跑的是本设备树编出来的产品，不是官方 recovery。

| 项 | 实测值 |
|---|---|
| 系统 | Android 16 / `BP4A.251205.006` / test-keys |
| 构建时间 | `Thu Oct 29 11:59:58 CST 2026` |
| `init.svc.adbd` | **running** ← recovery 里 adb 直接可用 |
| `ro.recovery.ui.margin_width/height` | **52 / 52** |
| `ro.sf.lcd_density` | 520 |
| `sys.usb.controller` | `a600000.dwc3` |
| 当前槽位 | `_a` |

### 7.2 adb 直接切 sideload

```bash
$ adb reboot sideload
[6s] sideload          # 6 秒进入，不需要在屏幕上点菜单
```

### 7.3 sideload 传输

```bash
$ adb -d sideload lineage-23.2-*-pandora.zip
serving: '...zip'  (~20%)      # 40 秒传了 20%，约 13 MB/s
```

recovery 日志（`/tmp/recovery.log`）：

```
I minadbd : usb_ffs.cpp:275 opening control endpoint /dev/usb-ffs/adb/ep0
I minadbd : adb.cpp:426 authentication not required
I minadbd : minadbd_services.cpp:111 sideload-host file size 2849547144, block size 65536
```

**没有** `failed to write USB descriptors: No such process` —— 之前那条导致
`Total xfer: 0.00x` 的报错不再出现。

### 7.4 镜像结构

| 项 | 值 |
|---|---|
| 文件大小 | 104,857,600 B（= `BOARD_RECOVERYIMAGE_PARTITION_SIZE`） |
| md5 | `a64ee7ccef50634dbb088fe21c0b5d6c`（能启动的版本） |
| header_version | 4 |
| **kernel_size** | **0** —— 纯 ramdisk，与 TWRP 一致 |
| ramdisk | 18,196,842 B，起始偏移 4096，226 个文件 |

> **关于 kernel_size = 0**：本机 ABL 从 `boot_a` 取内核，recovery 分区只放 ramdisk。
> 依据是能正常启动的 `TWRP-3.7.1-xiaomi-sm8850` 镜像实测也是 `kernel_size=0`、
> ramdisk 起始 4096。所以 `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true` 必须保留。

### 7.5 ramdisk 关键组件

| 组件 | 大小 |
|---|---|
| `system/bin/recovery` | 2,737,280 B |
| `system/bin/init` | 2,306,072 B |
| `system/bin/minadbd` | 256,336 B |
| `system/bin/update_engine_sideload` | 2,798,912 B |
| `system/lib64/hw/bootctrl.canoe.so` | 85,488 B |
| `system/lib64/hw/android.hardware.boot@1.0-impl-1.1-qti.so` | 218,072 B |
| `system/lib64/libboot_control_client.so` | 68,832 B |

### 7.6 未验证

**OTA 应用阶段（`update_engine_sideload` 的 bootctrl 初始化）没有测到。**
传输在 20% 被主动中断，`update_engine` 还没开始 Init。

要完整验证需要跑完 2.8 GB 传输并让它写非当前槽（`_b`）。
bootctrl HAL 已经在 ramdisk 里，预期不会再报 `Error getting bootctrl v1.0 module`。

## 八、已知限制

| 限制 | 说明 |
|---|---|
| **不能编完整 ROM** | `m bacon` 需要 `vendor/xiaomi/pandora`（原厂 blob），本仓库不含。需从官方固件 `pandora_images_OS3.0.318.0.*.tgz` 提取 |
| sideload 应用阶段 | recovery 已带 bootctrl HAL，但 OTA 还要求 B 槽非空（A/B 设备） |
| 加密 | 上游 TWRP 树标注 pandora 的 decrypt 不稳定 |

## 九、目录结构

```
device/xiaomi/pandora/
├── AndroidProducts.mk          → lineage_pandora.mk
├── BoardConfig.mk              分区 / 内核 / recovery 配置
├── lineage_pandora.mk          LOS 产品定义
├── device.mk                   bootctrl HAL + recovery 属性
├── Android.bp / Android.mk     soong namespace + 子目录包含
├── prebuilt/                   原厂 Image(39,963,136 B) / dtb / dtbo.img
├── bootctrl/                   bootctrl.canoe.recovery
├── gpt-utils/                  UFS BSG + GPT 解析（bootctrl 依赖）
├── kernel-headers/             ufs ioctl 头
├── recovery/root/              init.recovery.qcom.rc / recovery.fstab / twres
└── system.prop
```
