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

## LineageOS 24.0 完整 ROM 进度

23.2 时代判断「完整 ROM 不可行」是错的。LOS **24.0** 的 manifest 里自带
`hardware/qcom-caf/sm8850`（116 MB），只是它只在自家 Gerrit 上，GitHub 镜像查不到。
用 `git ls-remote github.com` 判断 LOS 有没有某个仓库，方法本身就是错的。

| 依赖 | 状态 | 说明 |
|---|---|---|
| LOS 24.0 源码树 | ✅ | 1400 个项目 / 409 GB，见 `docs/los24-build-notes.md` |
| `device/xiaomi/sm8850-common` | ✅ | lolipuru 上游（标注 booted），165 个提交 |
| `vendor/xiaomi/sm8850-common` | ✅ | blobs |
| `hardware/qcom-caf/sm8850` | ✅ | 116 MB，含 `audio/primary-hal/configs/canoe` |
| `device/xiaomi/pandora` | ✅ | 本仓库 `device-trees/los24-pandora/` |
| `device/xiaomi/pandora-kernel` | ✅ | 从 stock OTA 提取，262 MB |
| `vendor/xiaomi/pandora` | ❌ | 机型专属 blobs，待从 OTA 提取 |

验收分级：

| 级别 | 内容 | 状态 |
|---|---|---|
| D1 | `lunch lineage_pandora-trunk_staging-userdebug` | ✅ 通过 |
| D2 | `m nothing`（全量 soong 分析） | ✅ 通过（30:07，0 error） |
| D3 | `mka bacon` 出 zip | ✅ **通过**（1.11 GB OTA 包） |
| D4 | 刷入并启动 | ⏸ 待刷机验证 |

D3 产物：

```
lineage-24.0-20261031-UNOFFICIAL-pandora.zip   1,188,353,697 字节
sha256 ed4c316b4d5ebd7a19db90df2504de8d02554999f7f137970d03d6fac7395ef8
```

包内 15 个分区（payload.bin 格式）：`boot` `dtbo` `init_boot` `vendor_boot`
`vendor` `vendor_dlkm` `system` `system_ext` `product` `system_dlkm` `odm`
`recovery` `pvmfw` `vbmeta` `vbmeta_system`。

副本：`D:\WSL\out\pandora\`

D2 已解决的问题（细节见 `docs/los24-build-notes.md`）：

1. `hardware/xiaomi` 不在 LOS manifest，但被 `common.mk` 写进 `PRODUCT_SOONG_NAMESPACES`
2. `vendor/xiaomi/sm8850-common` 的 blob 包过度声明依赖，触发 vendor 变体级联
3. `external/deqp` 的 git 索引被清空，缺 3545 个文件
4. `device/xiaomi/pandora-kernel` 缺失导致 `TARGET_NO_KERNEL_OVERRIDE` 未生效，
   `vendor/lineage/build/tasks/kernel.mk:140` 用到空的 `TARGET_KERNEL_VERSION`

机型树**无法从官方包反编译得到**——它是构建期配置，不随镜像发布，
只能根据 `build.prop` / `vintf manifest` / `init rc` / `fstab` 反推后手写。
可提取的只有 blobs 和内核设备树。


---

## 关键结论

1. **LOS 24.0 上完整 ROM 路线可行**：`hardware/qcom-caf/sm8850` 在 manifest 里自带。
2. **system-only 路线可行**：stock vendor 已是 Android 16（system-sdk 36），与 LOS 23.2 的 VNDK 同代。
3. **逻辑分区共 8 个**（取自 stock `vendor/etc/fstab.qcom`）：
   `system` `system_ext` `product` `mi_ext` `vendor` `vendor_dlkm` `system_dlkm` `odm`。
   常见 TWRP 设备树漏掉 `mi_ext`。
4. **`ALLOW_MISSING_DEPENDENCIES := true` 会掩盖真实依赖缺失**，表现为 aconfig 库重复定义类。
5. **`sys.usb.ffs.ready` 是 adb 与 fastboot 共用的全局标志**，切换模式必须先停旧服务再清零。
6. **`repo init` 的 `-g` 决定拉哪些项目**，加在 `sync` 上无效；漏组时 `repo sync` 静默跳过、不报错。
7. **GKI 内核跨机型共用**：pandora 与 popsicle 的 `kernel` 二进制 sha256 完全一致，
   但 `dtbo.img` 与 `vendor_dlkm` 是机型专属，不能复用。

---

## 许可证

`scripts/`、`tools/`、`docs/` 下的原创内容采用 MIT（见 `LICENSE`）。
`device-trees/` 下的内容来自 LineageOS 与 TWRP-Test 上游项目，沿用其原始许可证（Apache-2.0 等），
版权归各自作者所有。

本仓库不包含任何小米专有二进制文件、OTA 包或系统镜像；相关产物以 GitHub Release 形式分发。
