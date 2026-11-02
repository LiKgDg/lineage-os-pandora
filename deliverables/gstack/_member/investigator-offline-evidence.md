# 离线取证报告：KMI 世代错配 / fstab / CONFIG_PSTORE_RAM / fastboot-info

事故编号 INC-PANDORA-LOS24-001 ｜ 纯离线、零设备、只读（未改 `docs/`、`device-trees/`）
脚本与产物：`deliverables/gstack/_work/`（`kmi_scan.py` 为本次新增）

---

## 1. KMI 世代错配（核心）

### 1.1 结论

**LOS 构建里混装了两个内核世代的可加载模块。刷入的内核属于 A17 世代（`6.12.69`），但 `vendor_boot` 里 405/461、`vendor_dlkm` 里 366/402 个模块是 A16 世代（`6.12.23`），其 `module_layout` CRC 与内核期望值不同 → 全部无法加载。LOS 的 `modules.load` 150 条里，142 条指向错配模块，另 8 条指向根本不存在的文件，即 150 条中 0 条可加载。**

### 1.2 实测数字（我自己重算，与领队给的数完全一致）

`module_layout` CRC 取法：在 `.ko` 内定位 `__versions` 段的 `module_layout\0` 名字串，其前 8 字节即 `struct modversion_info.crc`（LE u64，MODULE_NAME_LEN=56）。
vermagic 取法：定位 `.modinfo` 段 `vermagic=` 到 NUL。

**`vendor_boot.img` ramdisk（`lib/modules/*.ko`）**

| | LOS | stock |
|---|---|---|
| `.ko` 总数 | **461** | **461** |
| vermagic `6.12.23-android16-5-gd8653a69a3aa-mi-4k SMP preempt mod_unload modversions aarch64` | **405** | 0 |
| vermagic `6.12.69-android16-6-4k SMP preempt mod_unload modversions aarch64` | 56 | **461** |
| CRC `0xe976b219`（A16 世代） | **405** | 0 |
| CRC `0x797f2b3e`（A17 世代） | 56 | **461** |
| `lib/modules/modules.load` 条数 | **150** | **172** |

CRC 与 vermagic 严格一一对应：`0xe976b219` ↔ `6.12.23-…`，`0x797f2b3e` ↔ `6.12.69-…`。

**`vendor_dlkm.img`（130,994,176 B，ext4，magic `0xEF53`@0x438）**

| vermagic | 数量 | CRC |
|---|---|---|
| `6.12.23-android16-5-gd8653a69a3aa-mi-4k …` | **366** | `0xe976b219` |
| `6.12.69-android16-6-4k …` | 36 | `0x797f2b3e` |

共 402 个 `.ko`，**366 个错配**。

**`system_dlkm.img`（29,941,760 B，ext4）**

| vermagic | 数量 | CRC |
|---|---|---|
| `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k …` | **103** | `0x797f2b3e` |

共 103 个 `.ko`，**全部正确**，且 vermagic 精确等于内核 release。

### 1.3 内核侧

`boot.img`（boot header v4，page=4096）kernel 段 @4096、len=41,511,424：

```
Linux version 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k (kleaf@build-host) (Android (14043575, +pgo, +bolt, +lto, +mlgo, based on r536225) clang version 19.0.1 …
```
（linux_banner @ kernel 偏移 19,267,866）

**CRC 基准值的确定（关键）**：内核期望的 `module_layout` CRC = **`0x797f2b3e`**。依据是两条独立证据互相印证——① stock 的 461 个 vendor_boot 模块全是该值，而 stock 能正常启动；② **LOS 自己的 `system_dlkm` 103 个模块也全是该值**，且其 vermagic 与内核 release 逐字相同。故 `0x797f2b3e` 是刷入内核的真值，`0xe976b219` 是外来世代。

### 1.4 `modules.load` 可加载率（按 LOS 自己的 150 条统计）

| 分类 | 条数 |
|---|---|
| CRC `0xe976b219`（错配，加载必失败） | **142** |
| CRC `0x797f2b3e`（可加载） | **0** |
| 文件在 ramdisk 内根本不存在 | **8** |
| **合计** | **150** |

**150 条里没有一条能加载成功。** 错配样本（均属启动关键）：`gh_arm_drv.ko`、`clk-qcom.ko`、`clk-rpmh.ko`、`gcc-alor.ko`、`camcc-canoe.ko`、`dispcc-canoe.ko`、`debugcc-canoe.ko`、`qti-regmap-debugfs.ko` 等。

8 条悬空条目：`mem_object.ko`、`metis.ko`、`mi_mem_epoll.ko`、`mi_mem_limit.ko`、`mi_schedule.ko`、`migt.ko`、`miloadtrace.ko`、`qcom_tzmem.ko`。已逐一在 `vendor_boot` ramdisk **与** `vendor_dlkm.img` 内查找，**两处均不存在**——是纯悬空引用（第二个独立缺陷）。

### 1.5 stock 172 条 vs LOS 150 条：差在哪

集合差异不是简单 22 条：**stock 独有 30 条，LOS 独有 8 条**（30 − 8 = 22 净差）。

**stock 独有的 30 条**（多为其它平台的驱动，属多平台清单，缺失无害）：
`bcl_soc, common, cpu_phys_log_map, dispcc-chora, dispcc-sm4450, gcc-chora, gcc-sm4450, kryo_arm64_edac, mem_fault_events, mi_extent_pool, mi_game, mi_kernel_monitor, mi_memory_monitor, mi_qmi_trace, mimon, nvmem_qfprom, os_cpu_qi, os_cpu_qs, perf_actuator, phy-qcom-ufs-qmp-v4-crow, pinctrl-ravelin, plat_common, powerinsight_interface, qcom-cpufreq-hw, qnoc-chora, qnoc-ravelin, rtg, tcsrcc-chora, videocc-chora, vip_sched`
注意 `phy-qcom-ufs-qmp-v4-crow.ko` 是 **crow 平台**的 UFS PHY，不是 pandora（canoe）的——说明 stock 的清单本身是跨机型合集，不能直接当基线。

**LOS 独有的 8 条** = 上面那 8 条悬空条目（全部不存在）。

**启动关键模块点名（按领队要求）**：
- `binder_gki.ko`：**在 LOS 的 150 条里**（是），且在 stock 172 条里（是）。但它在 LOS 侧属 142 条错配组 → 加载必失败。
- `arm_smmu.ko`：**在 LOS 的 150 条里**（是），stock 也在。同样属错配组。
- `ufs_qcom.ko` / `ufshcd_core.ko` / `mmc_core.ko` / `zram.ko`：**两侧清单里都没有**——这些在 pandora 上是编进内核（built-in）的，不通过 modules.load 加载，故不是差异点。

### 1.6 证据分级（按领队要求分开写）

**已证实（离线可复现的硬数字）**
1. 两个内核世代的 vermagic 串并存于 LOS 构建产物：`6.12.23-android16-5-gd8653a69a3aa-mi-4k` 与 `6.12.69-android16-6-4k`。
2. 两组 `module_layout` CRC 分别为 `0xe976b219` / `0x797f2b3e`，且与 vermagic 严格对应。
3. LOS 侧计数：vendor_boot 405/461 错配、vendor_dlkm 366/402 错配、system_dlkm 0/103 错配。
4. 刷入内核 release = `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`；内核期望 CRC = `0x797f2b3e`。
5. LOS `modules.load` 150 条中 142 条错配 + 8 条悬空 = 150 条全部不可加载。
6. LOS 与 stock 的 `.ko` 文件清单**数量相同（各 461）**但内容世代不同。
7. 8 条悬空条目在 ramdisk 与 vendor_dlkm 中均不存在。

**仍属推断（无设备侧日志直接证明）**
1. 「`binder_gki.ko` 加载失败 → hwbinder 不可用 → system_server 起不来 → 卡开机动画」——机制链条合理，但**没有 logcat/dmesg 直接证明**，属推断。
2. 「修好 vendor_boot 的 405 个模块即可启动」——**不成立或不足**：`vendor_dlkm` 还有 366 个错配模块，second-stage 挂载 `/vendor_dlkm` 后同样会加载失败。两处都得换，才谈得上「修好」。
3. 内核的 `VERMAGIC_STRING` 常量未在 kernel 段内以明文找到（`6.12.69-android16-6-4k` 字面量在 kernel 段内 0 命中，`vermagic=` 亦 0 命中），故**没有**用 vermagic 做判据，一律以 CRC 为准。CRC 判据不依赖此点。

---

## 2. fstab 四来源比对

四来源取到三个，第四个明确未取得。

| 来源 | 结果 |
|---|---|
| LOS `vendor/etc/fstab.qcom`（vendor.img，ext4） | **取得**，8,928 B |
| LOS `first_stage_ramdisk/fstab.qcom`（vendor_boot ramdisk） | **取得**，8,928 B，**与上者 sha256 完全相同**：`6a6f28e52f571132bbd66a60ff89e12a88557f662bad0ddba66c6f6635b55a09` |
| stock `first_stage_ramdisk/fstab.qcom` | **取得**，13,814 B，sha256 `391d51430df0cb45a916e5508ebed51fade8b13d9674d7d04ee438031b382f1b` |
| stock `vendor/etc/fstab.qcom`（vendor.img，**EROFS**） | **未取得**（见第 5 节） |

### 2.1 userdata 行 flags 差集（核心）

| 字段 | 只在 stock 有 | 只在 LOS 有 | 两侧共有 |
|---|---|---|---|
| `mnt_flags`（第 4 列） | **（无）** | **`atgc`** | 8 个：`noatime,nosuid,nodev,discard,reserve_root=32768,resgid=1065,fsync_mode=nobarrier,inlinecrypt` |
| `fs_mgr_flags`（第 5 列） | **（无）** | **（无）** | **11 个全同**：`latemount, wait, check, formattable, fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0, keydirectory=/metadata/vold/metadata_encryption, metadata_encryption=aes-256-xts:wrappedkey_v0, quota, reservedsize=128M, sysfs_path=/sys/devices/platform/soc/1d84000.ufshc, checkpoint=fs` |

逐项点名：`formattable` **有/有**、`check` 有/有、`latemount` 有/有、`wait` 有/有、`forceencrypt` 都无（用 `fileencryption`）、`encryption=` 都无 → **全部无差异**。

**两侧 userdata 行都含 `formattable`** → 「stock 有 / LOS 没有」假设**否证**。

`atgc` 安全性已单独核实：LOS `boot.img` kernel 段字符串表内存在 `",atgc"`（带前导逗号，f2fs 挂载选项数组的 token 形式，紧邻 `f2fs_enable_checkpoint` / `fs/f2fs/checkpoint.c`），共 15 处命中 → 内核**支持**该选项。且即便不支持也只会 `EINVAL` → 触发 `formattable` 重建，不会导致完全不启动。

### 2.2 `/metadata` 行

三来源**逐字节相同**：
```
/dev/block/by-name/metadata  /metadata  f2fs  noatime,nosuid,nodev,discard  wait,check,formattable,first_stage_mount
```
**文件系统是 f2fs**（确认领队指正：不是 ext4），两侧都含 `formattable`。LOS 第 57 行、stock 第 91 行。

### 2.3 其余记录差异

两侧共有的 27 个挂载点中，除 `/data` 外**其余 26 条逐字节相同**。
stock 独有 35 条，全部是 MIUI 私有：`/mnt/vendor/mi_ext` 及其 22 条 overlay 叠加、`/mi_ext`(bind)、`/mnt/vendor/vm-persist`、`/mnt/rescue`（后两者带 `nofail`）。LOS 无 `mi_ext` 分区内容，缺失属预期，不构成挂载失败。

**判读**：既然 LOS `/data` 同样带 `formattable`，孤儿密文在 LOS 下也应走「挂载失败→格式化→重建→启动」。LOS 不启动 ⇒ 失败点在 `/data` late-mount **之前**或格式化路径本身。fstab 层面**两侧等价**，不是差异来源。

---

## 3. `CONFIG_PSTORE_RAM=y`

`boot.img` kernel 段内 `IKCFG_ST` @ 19,439,624、`IKCFG_ED` @ 19,487,806，中间 48,174 B gzip（`1f8b0800`）→ 解压得内核配置 **223,592 B**（`_work/los_kernel_config.txt`）。

配置原文（逐行来自 IKCONFIG）：
```
CONFIG_PSTORE=y
CONFIG_PSTORE_DEFAULT_KMSG_BYTES=10240
CONFIG_PSTORE_COMPRESS=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
CONFIG_F2FS_FS=y
```
未启用：`CONFIG_PSTORE_FTRACE`、`CONFIG_PSTORE_BLK`、`CONFIG_PSTORE_ZONE`、`CONFIG_PSTORE_DEFLATE_COMPRESS`（均不存在于配置）。
`CONFIG_PSTORE_RAMOOPS` **不是 mainline Kconfig 符号**——ramoops 后端由 `CONFIG_PSTORE_RAM` 提供，该符号「缺失」不构成任何证据。

**裁定**：`docs/los24-build-notes.md` §33「`/sys/fs/pstore` 为空（内核未配置 ramoops）」的**括号判断是错的**（否证）。观察本身（目录为空）大概率真实，但不能推出未配置。

### 3.1 12 份 dtb 的 ramoops 节点核对

`device-trees/pandora-dt/original/base-parts/*.dtb`，自写 FDT 解析器逐份遍历：**12/12 全部含 `reserved-memory/ramoops-region`，且 12 份 `reg` 完全一致**。

`00_dtb_581542.dtb` 节点原文：
```
/reserved-memory/ramoops-region {
    compatible = "ramoops";
    reg = <0x00000000 0xff400000 0x00000000 0x00200000>;
    console-size = <0x00100000>;
    pmsg-size = <0x00100000>;
    phandle = <0x000003b3>;
};
```
基址 `0xff400000`、大小 `0x200000`=2 MiB；`console-size` 1 MiB + `pmsg-size` 1 MiB 恰为 2 MiB，自洽。

**「无 ECC」独立证实**：12 份 dtb 该节点属性集合均为 `['compatible','console-size','phandle','pmsg-size','reg']`，**无 `ecc-size`**。ramoops 的 ECC 由 DT `ecc-size` 开启，缺失即无 ECC → 静态分析报告「ramoops 链路完整、无 ECC」**成立（证实）**。

---

## 4. `fastboot-info.txt` 存在性

**结论：全仓库、全构建产物中不存在该文件。**

| 遍历位置 | 结果 |
|---|---|
| LOS OTA zip `lineage-24.0-20261101-UNOFFICIAL-pandora.zip` | 共 **7 条**：`META-INF/com/android/{metadata,metadata.pb,otacert}`、`apex_info.pb`、`care_map.pb`、`payload.bin`、`payload_properties.txt` → **无** |
| `UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/` 目录 | 递归：`flash_fastbootd.txt` + `images/` 下 15 个 `.img` → **无** |
| `sysonly/` | 8 个文件（`product/recovery/super(+part00~03)/system/system_ext.img`）→ **无** |
| stock OTA zip `pandora-ota_full-…zip` | 共 **7 条**，同上结构 → **无** |
| 全树 `find . -iname "*fastboot*info*"` | **0 命中** |

**机制真实但无载体**：`platform-tools/fastboot.exe`（2,429,080 B）内含
`fastboot-info.txt`（15 处）、**`if-wipe` @ 1,985,597**、
`Flashing from hardcoded images. fastboot-info.txt is empty or does not exist`、
`Erase successful, but not automatically formatting.` @ 1,986,084、
`File system type %s not supported.`、` -w    Wipe userdata.` @ 1,995,256。
→ 机制存在，但无任何产物携带该文件，fastboot 走 hardcoded 回退分支。**假设否证。**

**假成功的真实成因（日志实证）**：`docs/flash-log-1458.txt` 第 42–47 行 —— `Erasing 'metadata' OKAY [4.020s]` → `Erase successful, but not automatically formatting.` → `File system type raw not supported.` → 退出码 0 → 脚本打印 `✓ userdata 已清空`。同形态在 `flash-log-1609.txt`(46–51)、`flash-log-v32-1809.txt`(46–51) 复现。**四份日志中 `Erasing 'userdata'` 出现 0 次，`Erasing 'metadata'` 出现 3 次**——userdata 从未被擦。

---

## 5. 未取得 / 已知局限

1. **stock `vendor.img` 的 `/etc/fstab.qcom` 未取得（唯一缺项）。** 该镜像为 **EROFS**（magic `e0f5e1e2`@0x400，root_nid=58，`feature_incompat=0x1`）。目标文件 inode 为 `i_size=13814`、`i_format=0x0006` → `datalayout=3`（`EROFS_INODE_FLAT_COMPRESSION`，LZ4 压缩 inode）。**卡在 compacted lcluster index 寻址**：`i_u` 对压缩 inode 是 `compressed_blocks`(=1) 而非块地址，最初误当 `raw_blkaddr` 去解 block 1，解出的是 `build.prop`（已排除）；随后按 blkaddr 候选(13147)、copyright 字面量命中点、9 个候选块 × 多偏移/多长度共 386 个候选穷举，均未命中。按时间盒**主动放弃**。
   **缓解证据（推断，非证实）**：该 inode `i_size=13814`，与已取得的 stock `first_stage` 字节数**完全相同**；且 LOS 侧 `vendor/etc` 与 `first_stage` 是 sha256 相同的同一文件。→ **推断** stock 两者同内容，高置信但未证实。补证方法：`fsck.erofs --extract` 或设备侧 `adb pull /vendor/etc/fstab.qcom`。
2. **内核 `VERMAGIC_STRING` 常量未定位**：kernel 段内 `6.12.69-android16-6-4k` 字面量与 `vermagic=` 均 0 命中。故全文**不以 vermagic 字符串为判据**，一律以 `module_layout` CRC 为准（CRC 判据不依赖此点）。这也解释了为何 stock 的 A17 世代模块 vermagic 是短形式 `6.12.69-android16-6-4k`，而 LOS 自己的 `system_dlkm` 是含完整 release 的长形式——两者 CRC 相同（`0x797f2b3e`），说明 vermagic 字符串的两种写法在内核侧等价。
3. **`fastboot -w` 为何只挑 `metadata` 而不擦 `userdata`：机理未取得。** 现象有 3 份日志互证（证实），二进制内未找到硬编码 wipe 列表（`misc` 字符串 0 命中）。
4. **`/sys/fs/pstore` 为空的真实原因未取得。** 配置与 DT 均已证实存在，空目录的三个候选（无崩溃 / DT 未 probe / console 默认不写）无法离线区分。
5. **未做**：未修改 `docs/`、`device-trees/` 任何文件；未刷机；未接触设备。中间产物在 `deliverables/gstack/_work/`（`stock_vendor.img` 589 MB、`stock_vendor_boot.img` 101 MB、`los_kernel.bin` 41 MB、两份 cpio 50/55 MB、`stock_vendor_ramdisk.cpio` 等），如需清理请告知。
