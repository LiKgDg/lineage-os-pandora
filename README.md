# lineage-os-pandora

Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）的 LineageOS 移植与 TWRP 恢复环境工作区。

本仓库记录从原厂固件解包、设备树生成、system-only 编译到刷机验证的完整过程与工具链，
以及过程中踩到的坑和对应修复。

---

## 当前状态

### 已完成

| 模块 | 说明 |
|---|---|
| 固件解包 | `tools/payload_dump.py` 解析 OTA payload，导出 57 个分区；`--verify` 按 manifest 的 sha256 校验 |
| Blob 清单 | `tools/gen_blob_list.py` 生成 `proprietary-files.txt`（6135 条） |
| 设备树生成 | `tools/gen_vendor_bp.py` 生成 soong 包（5811 个模块） |
| system-only 编译 | `system.img` 892 MB / `system_ext.img` 435 MB / `product.img` 509 MB |
| recovery 编译 | 含 `fastbootd`，`kernel_size=0`，adb 免认证 |
| super 拼装 | `lpmake` 组装 8 个逻辑分区，`lpdump` 校验通过 |
| 模式切换补丁 | `rc-mode` + USB 重枚举补丁（见 `docs/recovery-mode-switch-patch.md`） |
| **TWRP 编译** | `twrp-16.0` 编出 `recovery.img` 104,857,600 B，`kernel_size=0` / `header_version=4` |
| **TWRP 运行** | 刷入 `recovery_a` 后正常启动，`ro.twrp.version=3.7.1_16-Xiaomi_17_Pro`，8 个逻辑分区识别，触摸驱动加载 |

### 未完成 / 已知问题

| 问题 | 现状 | 下一步 |
|---|---|---|
| system-only 未启动 | `super.img` 刷入后设备回落 stock，未进系统 | 需抓 `logcat` / `pstore` 定位首次启动失败点 |
| fastbootd 热切 | `rc-mode fastboot` 落到 bootloader 而非 fastbootd | `sys.usb.ffs.ready` 时序问题，见文档 |
| TWRP 数据解密 | `/data` 能挂载但 CE 区未解密，日志报 `Unknown password type` | Android 16 的 spblob 新格式（`.e0`/`.p1`/`.spblob`）TWRP 3.7.1 解析不了，属上游适配问题 |
| 完整 ROM 设备树 | `sm8850-common` 已定位，但机型树/blobs/kernel/`hardware/qcom-caf/sm8850` 缺 | 见下节"完整 ROM 的缺口" |


---

## 目录结构

```
.
├── docs/                      设计与问题分析文档
│   ├── twrp-build-notes.md    TWRP 编译九个坑的完整记录
│   ├── wsl-adb-guide.md       WSL 环境使用 adb 的完整指南
│   ├── recovery-mode-switch-patch.md   recovery 模式切换补丁说明
│   ├── phase1-full-rom-report.md       完整 ROM 路线评估
│   ├── phase1b-system-only-port.md     system-only 执行报告
│   ├── logs/                  刷机与 sideload 日志
│   └── ref/                   参考设备的配置（oneplus sm8850）
├── scripts/
│   ├── build/                 编译与源码同步（含 build_twrp.sh）
│   ├── flash/                 镜像拼装与刷机
│   ├── patch/                 recovery / USB 补丁
│   ├── device/                设备树装配脚本与片段
│   └── maintain/              磁盘、证书、环境维护、缺失项目补齐
├── device-trees/
│   ├── los-pandora/           LineageOS 侧设备树与 blob 清单
│   └── twrp-pandora/          TWRP 侧设备树（来自 TWRP-Test/sm8850）
├── tools/                     OTA 解包与设备树生成工具
│   ├── payload_dump.py        payload 解析，支持 --list / --verify
│   ├── gen_blob_list.py       ELF 依赖递归生成 blob 清单
│   ├── gen_vendor_bp.py       生成 soong 包（当前使用）
│   └── gen_vendor_mk.py       生成 make 包（已废弃，见文件头说明）
└── releases/                  镜像发布说明（实际镜像见 GitHub Release）
```

---

## 快速开始

### 1. 解包原厂固件

```bash
# 只看清单（含增量包检测）
python3 tools/payload_dump.py --list pandora-ota_full-*.zip

# 解出全部分区，并按 manifest 的 sha256 校验
python3 tools/payload_dump.py pandora-ota_full-*.zip stock/ --verify

# 只解指定分区
python3 tools/payload_dump.py pandora-ota_full-*.zip stock/ system vendor odm --verify
```

**增量包会被直接拒绝**（退出码 2）。`payload_dump.py` 只能还原完整包；
`SOURCE_COPY` / `*BSDIFF` 这类操作需要源镜像才能重建，单个增量包做不到。

### 2. 生成 blob 清单与 soong 包

```bash
# 参数形式：<输出目录> <分区>=<挂载点> [...]
python3 tools/gen_blob_list.py vendor/xiaomi/pandora \
    vendor=/mnt/pv odm=/mnt/po system_ext=/mnt/pse

# 参数形式：<device_vendor_dir>
python3 tools/gen_vendor_bp.py vendor/xiaomi/pandora
```

产出 `proprietary-files.txt`、`proprietary/<part>/...`、`Android.bp`、`<device>-vendor.mk`。

### 3. 编译 system-only 镜像

```bash
bash scripts/build/build_sysonly.sh
```

依赖：LineageOS 23.2 源码树、`JAVA_HOME` 指向预编译 JDK、干净 `PATH`。

### 4. 拼装 super 并刷机

```bash
bash scripts/flash/make_super.sh          # 生成 sysonly/super.img
bash scripts/flash/flash_super.sh         # 设备需在 bootloader fastboot
```

镜像获取见 [`releases/README.md`](releases/README.md)。

### 5. 编译并刷入 TWRP

```bash
bash scripts/build/build_twrp.sh 10       # 前台编译，GUI 终端可见进度条
```

产物 `out/target/product/sm8850/recovery.img`，校验与踩坑见
[`docs/twrp-build-notes.md`](docs/twrp-build-notes.md)。

---

## 完整 ROM 的缺口

`AlexZorzi/android_device_xiaomi_sm8850-common`（分支 `lineage-24.0`）提供了公共设备树，
但完整 ROM 还缺这些，缺一个都编不了：

| 依赖 | 状态 | 说明 |
|---|---|---|
| `device/xiaomi/sm8850-common` | ✅ 已有 | 公共层，被机型树 inherit |
| `device/xiaomi/pudding` / `popsicle` | ❌ 缺 | 机型树，负责 `PRODUCT_NAME` 与机型 blobs |
| `vendor/xiaomi/sm8850-common` | ❌ 缺 | `common.mk` 里 `inherit-product` 硬引用 |
| `kernel/xiaomi/sm8850` | ❌ 缺 | OSS 内核或预编译内核 |
| `hardware/qcom-caf/sm8850` | ❌ 缺 | **最大阻塞**，LOS 官方最高 `sm8750`，而 `AUDIO_HAL_DIR` 写死指向它 |

`device/xiaomi/pudding` 这类机型树**无法从官方包反编译得到**——它是构建期配置，
不随镜像发布，只能根据 `build.prop` / `vintf manifest` / `init rc` / `fstab` 反推后手写。
可提取的只有 blobs 和内核 DTS。


---

## 关键结论

1. **完整 ROM 路线不可行**：LineageOS 23.2 最高只到 `hardware/qcom-caf/sm8750`，SM8850 缺 CAF 源码。
2. **system-only 路线可行**：stock vendor 已是 Android 16（system-sdk 36），与 LOS 23.2 的 VNDK 同代。
3. **逻辑分区共 8 个**（取自 stock `vendor/etc/fstab.qcom`）：
   `system` `system_ext` `product` `mi_ext` `vendor` `vendor_dlkm` `system_dlkm` `odm`。
   常见 TWRP 设备树漏掉 `mi_ext`。
4. **`ALLOW_MISSING_DEPENDENCIES := true` 会掩盖真实依赖缺失**，表现为 aconfig 库重复定义类。
5. **`sys.usb.ffs.ready` 是 adb 与 fastboot 共用的全局标志**，切换模式必须先停旧服务再清零。

---

## 许可证

`scripts/`、`tools/`、`docs/` 下的原创内容采用 MIT（见 `LICENSE`）。
`device-trees/` 下的内容来自 LineageOS 与 TWRP-Test 上游项目，沿用其原始许可证（Apache-2.0 等），
版权归各自作者所有。

本仓库不包含任何小米专有二进制文件、OTA 包或系统镜像；相关产物以 GitHub Release 形式分发。
