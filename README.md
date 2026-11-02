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
| **LOS 24 完整 ROM 启动失败** | **根因已定案（离线 + 实机交叉验证）**：内核模块与内核 KMI 世代错配——`vendor_boot` 405/461、`vendor_dlkm` 366/402 是 6.12.23（android16-5）世代，内核是 6.12.69（android16-6）；`module_layout` CRC `0xe976b219` ≠ `0x797f2b3e`（后者已由 PixelOS 实机启动验证）。另有**清单与索引缺陷**：清单差集 66 条（实机折算 41 个真会漏加载），5 个索引文件也是 A16 生成的 | 按 `deliverables/gstack/_member/qa-fix-runbook.md` 的 **A2+ 整目录替换**执行（`vendor_ramdisk/lib/modules/`、`vendor_dlkm/lib/modules/`、`system_dlkm_flatten/` 三处整体替换，`system_dlkm/` 不动），然后重刷。验收判据：三处与 PixelOS 对应目录**逐字节相同**。✅ **已完成**：门禁 461/402/103 全 PASS（CRC 不符 0、悬空 0），同名索引 C4 对账通过；已出整包 `releases/Fastboot_lineage_pandora-20261102-1426.zip`，包内 A16 世代模块计数 **0**（此前坏包 53 / 366 / 102）。**待真机刷入验收**，方法见「快速开始 §7.1」 |
| system-only 未启动 | `super.img` 刷入后设备回落 stock，未进系统 | 与上一行同源，先用同一门禁脚本排除模块问题，再抓 `logcat` / `pstore` |
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
│   └── maintain/              磁盘、证书、环境维护、缺失项目补齐、内核模块门禁
├── device-trees/
│   ├── los-pandora/           LineageOS 侧设备树与 blob 清单
│   └── twrp-pandora/          TWRP 侧设备树（来自 TWRP-Test/sm8850）
├── tools/                     OTA 解包与设备树生成工具
│   ├── payload_dump.py        payload 解析，支持 --list / --verify
│   ├── gen_blob_list.py       ELF 依赖递归生成 blob 清单
│   ├── gen_vendor_bp.py       生成 soong 包（当前使用）
│   └── gen_vendor_mk.py       生成 make 包（已废弃，见文件头说明）
├── deliverables/gstack/       工程分析报告与取证工作区
│   ├── offline-evidence-closure-los24-kmi-2026-11-01.md   启动失败根因定案（模块 KMI 错配）
│   ├── pixelos-cross-reference-2026-11-02.md              PixelOS 交叉验证（缺陷范围圈定、方案翻转）
│   ├── _member/               各角色原始产出（修复手册、实验矩阵、离线取证）
│   └── _work/                 取证脚本与文本证据，见其中 README.md
└── releases/                  镜像发布说明（实际镜像见 GitHub Release）
```

---

## 执行边界：哪些在 WSL 里跑

**Windows 工作区只做「调度 + 收证据」，编译与解包一律在 WSL 的 ext4 内完成，本项目目录不落 `.ko` / 内核源码 / `out/`。**

| 在 WSL 里跑（产物也只留 WSL） | 在 Windows 工作区 |
|---|---|
| `repo sync`：`/root/los24`（LOS 24.0，1400 项目 / 409 GB）、`/root/android/lineage`（TWRP） | 文档、脚本、设备树（`docs/` `scripts/` `device-trees/` `tools/`） |
| `make`：`out/target/product/pandora/**`（含 1069 个 `.ko`） | 小体量一手证据：fstab 文本、`los_kconfig.txt`、刷机日志、`getvar` |
| 内核解包 / dtb / `mkbootimg` / `lpmake` | 哈希与统计：sha256、`module_layout` CRC 分布、清单对账表 |
| 镜像取证：`debugfs`、`mount -t erofs`、`cpio`、`lz4` | 刷机：`platform-tools/`（设备由 Windows 侧持有） |
| 模块校验：`modinfo -F vermagic`、`modprobe --dump-modversions` | 纯 Python 只读解析器（`ext4mini.py` 等，只吐文本） |

判定标准是「能不能从现有输入重算」：能重算的留在 WSL，不能重算的回写项目。

- 中间态落 `/root/work/gstack/`，**不要放 `/tmp`**（WSL 空闲会重启，`/tmp` 清空），**也不要放 `/mnt/c`**（9p 协议慢、缺可执行位与符号链接，且旧世代 `.ko` 会在共享目录里存活）。
- 例外：**小体积文本证据**（fstab、`los_kconfig.txt`、`modules.load`、CRC 报表）和**不再改动的镜像副本**（stock 的 `vendor_dlkm` / `system_dlkm`，共约 75 MB）落在 `deliverables/gstack/_work/`，因为它们要随报告一起交付；含 `.ko` 的实验目录仍留在 WSL 内部。
- 完整分析与踩坑记录见 [`deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md`](deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md) §5。

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

### 6. 出包前校验内核模块（必做）

```bash
# 构建树模式：判据是 module_layout 的 CRC，最精确
bash scripts/maintain/verify_kernel_modules.sh

# 镜像模式：直接查即将刷进去的那几个 .img，不需要 root、不需要挂载
bash scripts/maintain/verify_kernel_modules.sh --images /path/to/images

# 整目录替换的验收：五个索引必须与已知可启动的出货构建逐字节相同
bash scripts/maintain/verify_kernel_modules.sh --ref /path/to/pixelos/vendor_dlkm/lib/modules
```

退出码 0 才允许刷机。构建树模式扫四个目录——`vendor_ramdisk`、`vendor_dlkm`、
`system_dlkm` 的**版本化目录**与 **flatten 副本**——做五查（C4 仅在给 `--ref` 时启用）：

| 检查 | 内容 | 是否阻塞 |
|---|---|---|
| C1 | 每个 `.ko` 的 `module_layout` CRC 等于内核期望值 | ✅ 硬门禁 |
| C1b | 每个 `.ko` 的 vermagic 版本段与期望 KMI 一致 | ⚠️ 告警 |
| C2 | `modules.load` 每条都能在目录内找到同名文件 | ✅ 硬门禁 |
| C3 | `modules.load` 无重复条目 | ⚠️ 告警 |
| C4 | `modules.*` 索引与参考构建（`--ref`）逐字节一致 | ✅ 硬门禁（启用即阻塞） |

> C1b 只告警是有原因的：`CONFIG_MODVERSIONS=y` 时内核 `same_magic()` 只比较
> vermagic 第一个空格**之后**的标志位，版本段被跳过——所以版本串不同不必然加载失败，
> 真正决定成败的是 CRC。C3 同理：原厂 stock 自己就有 263 条重复且能正常开机。

> C4 补的是另一个独立缺陷面：C1 只覆盖 `.ko`，**管不到 `modules.alias` / `.dep` /
> `.softdep` / `.blocklist` 这几份由模块集生成的索引**。索引是 A16 生成的、模块是 A17，
> C1/C2/C3 会全 PASS，但 autoload 与依赖解析整体走错——`.ko` 全换对了照样起不来。
> 本机模块是固定预编译产物，所以判据只能是「与已知可启动的出货构建逐字节相同」，
> 用 md5 判等，不做启发式推导。只比双方都存在的文件；单侧存在只告警。

镜像模式查的是镜像内旧世代 vermagic 字符串的计数。判据是二值的：**已知正确的 stock
镜像是 0，本次出问题的 LOS 镜像是 53 / 366 / 102**。它拦不住理论上「CRC 变了但
vermagic 没变」的边角情况，但能拦住实际发生的这一类。

三处成组验收（比 `.ko` 与索引的**全文件 md5**，不依赖 kmod，Windows 侧也能跑）：

```bash
bash scripts/maintain/verify_index_ref.sh \
    --los /root/los24/out/target/product/pandora \
    --ref /path/to/pixelos
```

判据：三处共 981 个文件全部「内容不同 0 / 仅一侧 0」。`modules.order` 与
`modules.builtin*` 自动排除——它们本来就随构建路径变，做成门禁会误杀。

**刷机脚本已经接上这道闸**：`flash_los_full.sh` 与 `flash_los_with_recovery.sh` 在刷之前
自动跑 `--images`，不通过就退出（退出码 2）。要跳过必须显式写 `--no-check` /
`LOS_SKIP_KMI_CHECK=1`——不能靠「没注意」。

两个脚本的分工：`clean_stale_modules.sh` 负责**删干净** `out/` 里的旧世代残留，
`verify_kernel_modules.sh` 负责**判干净**。编译前后各跑一次最稳。

```bash
bash scripts/maintain/clean_stale_modules.sh --dry-run   # 先看要删什么
bash scripts/maintain/clean_stale_modules.sh             # 再删
```

### 7. 刷入 LOS

#### 7.1 整包（首次启动验收必须走这条）

```bash
# 只过闸不刷：包结构 + fastboot 版本 + 镜像内模块世代 + 设备状态
bash scripts/flash/flash_fastboot_package.sh --preflight

# 真刷（会问一次，输入 YES）
bash scripts/flash/flash_fastboot_package.sh
```

整包路径与逐分区路径的本质差别是 `fastboot -w update` 会读包内的 `fastboot-info.txt`：
它自己 `reboot fastboot`、`update-super`、按声明顺序刷逻辑分区，并执行
`if-wipe erase userdata` / `erase metadata`。**逐分区脚本没有这些**，所以首次启动验收
必须用整包——否则 wipe 没发生，卡住的现场就是「孤儿密文」而不是任何真实缺陷。

脚本把三个只能靠工具拦的陷阱做成硬闸：

| 闸 | 拦什么 | 不过的后果 |
|---|---|---|
| G1 | 包内缺 `fastboot-info.txt` / `update-super` / `if-wipe erase userdata` | `-w` 只擦 metadata，`/data` 变孤儿密文 |
| G2 | fastboot 主版本 < 34 | 静默忽略 `fastboot-info.txt`：super 不更新、data 不擦、vbmeta 不施加，**屏幕与退出码都显示成功** |
| G3 | 镜像内仍有 `6.12.23-android16-5` 世代模块 | 刷了必然卡第一屏 |

刷完还会做一次事后校验（`--check-log` 可对历史日志单独复跑）：日志里必须有
`Erasing 'userdata'`、必须有 super 的写入痕迹、且 `Sending '<分区>'` 的集合不能出现
`abl` / `xbl` / `tz` / `uefi` 等固件分区——老版 fastboot 走 legacy 路径时会遍历 zip 里
所有 `*.img`，拿同一套命令刷第三方整包就会写 bootloader。

#### 7.2 逐分区（更新 / 局部重刷用）

```bash
bash scripts/flash/flash_los_full.sh --img /path/to/images
```

会先跑 KMI 检查、再确认设备已在 fastbootd、然后逐个分区刷入，全程 tee 到
`docs/logs/<UTC>-flash-los-full.log`。退出码 0 才是真成功——**别只看屏幕上的
「中断于第 N 个」**，那行文字以前是唯一的信号，而脚本的 `$?` 一直是 0。

> 这个脚本**不 wipe、不走 `update-super`、不刷 `pvmfw` 与 `recovery`**，
> 且默认镜像目录是 `D:/WSL/out/pandora/modfix`（可能落后于最新构建）。
> 拿它做首次启动验收会同时丢掉「模块正确」和「真 wipe」两个前提。

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
| D4 | 刷入并启动 | 🔴 **不通过，根因已定案**：模块 KMI 世代错配。修复路径与覆盖率已验证，见 [`deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md`](deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md) |

D3 产物：

```
lineage-24.0-20261031-UNOFFICIAL-pandora.zip   1,188,353,697 字节
sha256 ed4c316b4d5ebd7a19db90df2504de8d02554999f7f137970d03d6fac7395ef8
```

包内 15 个分区（payload.bin 格式）：`boot` `dtbo` `init_boot` `vendor_boot`
`vendor` `vendor_dlkm` `system` `system_ext` `product` `system_dlkm` `odm`
`recovery` `pvmfw` `vbmeta` `vbmeta_system`。

副本：`D:\WSL\out\pandora\`

后续另有一次 **A17 重建**（11-01 18:26，`lineage-24.0-20261101-UNOFFICIAL-pandora.zip`，
1,189,706,189 字节），该产物**从未刷入**，是本次根因分析的对象。两次产物都带着同一个模块世代缺陷。

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
8. **换内核必须连模块一起换，且「文件名清单一致」不能当「内容一致」**。本次启动失败的根因是
   内核换成了 stock 的 6.12.69，而 `vendor_ramdisk/` 与 `vendor_dlkm/` 里仍是 6.12.23 的模块：
   两侧 `.ko` 文件名 461 个全同，**内容 411 个不同**，`module_layout` CRC `0xe976b219` vs `0x797f2b3e`，
   `modules.load` 150 条可加载 0 条。排除级证据必须是哈希或 CRC，不能是清单。
9. **本机模块是一份固定的预编译产物，不是源码构建**。PixelOS（同机型 A17 出货构建）的
   461 + 402 个模块与 stock **逐字节完全相同**，五个 `modules.*` 索引 md5 也相同。
   所以修复方式是「整目录替换」，不是「重编内核」——重编这条路在这个设备上不存在。
   实机验证：PixelOS 已启动（`sys.boot_completed=1`），抽样 40 个 `.ko` + 5 个索引
   **全部与镜像 md5 相同**，即「镜像 = 运行态」。
10. **手写 `modules.load` 与陈旧索引是一类独立的缺陷源**。LOS 的清单不只多了 8 条幽灵，
    还少了 66 条（按实机 `lsmod` 折算，**41 个真会漏加载**）；更硬的是
    `modules.alias` / `.dep` / `.softdep` **也全是 A16 生成的**，autoload 与依赖解析会全错。
    用厂商随包发布的清单 + 索引，不要手工裁剪。
11. **`fastboot-info.txt` 是 `fastboot -w` 的行为来源**。出货构建里它写着
    `if-wipe erase userdata` + `if-wipe erase metadata`；本项目的 OTA 包里没有这个文件，
    `-w` 因此只擦了 metadata——「`✓ userdata 已清空`」是假成功。
12. **失败后怎么取证**：设备 `panic_on_oops=1`、ramoops 通道实测可用。
    若 LOS panic，刷回 PixelOS 后读 `/sys/fs/pstore/console-ramoops-0` 就能拿到栈
    （ramoops 是预留内存，跨重启保留）。纯 userspace hang 留不下（`hung_task_panic=0`）。

---

## 从设备/固件取内容的三种路径

三条路径不是替代关系，各自覆盖不同的东西：

| 路径 | 命令 | 拿到什么 | 前提 | 覆盖 |
|---|---|---|---|---|
| **A 全量 OTA** | `python3 tools/payload_dump.py <zip> stock/ --verify` | 57 个分区镜像，离线可复跑 | 有官方 OTA 包 | `vendor` `odm` `system` `system_ext` `product` `*_dlkm` `boot` `vendor_boot` `dtbo` `vbmeta` `mi_ext` 等 |
| **B adb pull** | `bash scripts/maintain/dump_device.sh --mode pull` | 运行态文件树 `/vendor` `/odm` `/system_ext` `/product` `/system` | shell 权限即可 | 运行态内容、当前挂载状态；root-only 文件会被跳过并列出 |
| **C 分区 dd** | `bash scripts/maintain/dump_device.sh --mode dd --parts persist,devinfo` | 分区级镜像 | **必须 root**（`adb root` 或 `su`） | `persist` `devinfo` `frp` `modemst*` 这类 **OTA 里没有**的分区 |

`bash scripts/maintain/dump_device.sh --list` 会列出设备全部 166 个分区，标注每个该走哪条路径。

实测前提（pandora）：`/dev/block/by-name` 可以列，但**块设备读取 `Permission denied`**，所以 C 必须 root；B 在 shell 下可拉，`/vendor/etc` 750 个文件实测全部到手。

补 blobs 不需要 C：`bash scripts/maintain/extract_blobs_from_ota.sh` 走 A 路径，
实测 211 条缺失里有 206 条就在本地镜像内。

## 已发布的设备树仓库

设备树已拆成三个独立仓库发布，`lineage.dependencies` 互相引用，可直接被 `roomservice` / `repo` 取用：

| 仓库 | 内容 | 说明 |
|---|---|---|
| [`LiKgDg/android_device_xiaomi_pandora`](https://github.com/LiKgDg/android_device_xiaomi_pandora) | 机型树（29 文件） | 本仓 `device-trees/los24-pandora/` 的同源副本 + LICENSE / NOTICE / README |
| [`LiKgDg/android_device_xiaomi_sm8850-common`](https://github.com/LiKgDg/android_device_xiaomi_sm8850-common) | 通用设备配置（188 文件） | 上游 `lolipuru/android_device_xiaomi_sm8850-common`(lineage-24.0) 快照，为 pandora 适配 |
| [`LiKgDg/android_device_xiaomi_pandora-kernel`](https://github.com/LiKgDg/android_device_xiaomi_pandora-kernel) | 清单与校验（10 文件） | **不含内核二进制**（小米分发物）；含 1112 条 sha256 清单与 `verify.sh` |

三个仓库均为 **实验性**：能编包已验证，能启动未验证，机型专属 blobs 尚未生成。
细节见 [`docs/publish-plan.md`](docs/publish-plan.md) 与各仓 README。

## 许可证

`scripts/`、`tools/`、`docs/` 下的原创内容采用 MIT（见 `LICENSE`）。
`device-trees/` 下的内容来自 LineageOS 与 TWRP-Test 上游项目，沿用其原始许可证（Apache-2.0 等），
版权归各自作者所有。

本仓库不包含 OTA 包与系统镜像——体积过大，且属小米分发物，相关产物以 GitHub Release 形式分发。

唯一例外是 `device-trees/pandora-dt/original/` 下从原厂固件提取的设备树二进制：
2 个 `.dtbo` 与 12 棵基础 `.dtb`，共约 7.7 MB。入库理由是它们是 `make merge` / `make verify`
的**校验基准**——不入库则新克隆无法复跑校验，只能要求每个使用者重新解开 9 GB 的 OTA 包。
清空该目录后 `make extract` 会从原包重新补齐。
