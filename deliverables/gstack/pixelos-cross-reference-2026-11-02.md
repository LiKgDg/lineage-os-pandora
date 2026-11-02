# PixelOS 交叉验证：第三个独立基准，把缺陷范围精确圈到「模块二进制 + 索引」

**日期**：2026-11-02
**取证对象**：`PixelOS_pandora-17.0-20261102/`（同机型 pandora / SM8850、Android 17 基线、已构建产物）
**对照物**：LOS 24（`UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images/`）、stock（`pandora-ota_full-OS4.0.5.0.XBLCNXM`）
**前置文档**：`offline-evidence-closure-los24-kmi-2026-11-01.md`（KMI 定案）、`_member/qa-fix-runbook.md`（修复手册）

---

## 📌 TL;DR

1. **缺陷范围被精确圈定**：PixelOS 与 LOS 的 `vendor_boot` ramdisk **文件清单完全相同（468 / 468）**，其中 `first_stage_ramdisk/fstab.qcom` 与 `lib/modules/modules.load.recovery` **逐字节相同**；全部差异只有 **405 个 `.ko` + 5 个 `modules.*` 索引文件**。LOS 的 ramdisk 脚手架是对的，坏掉的只有模块层。
2. **本机模块是一份固定的预编译产物，不是源码构建**：PixelOS 的 461 个 `vendor_boot` 模块与 stock **逐字节相同（461/461）**，`vendor_dlkm` 402/402 相同，连 `modules.alias/dep/softdep/blocklist/load` 五个索引文件的 md5 都一致。**两个互不相干的 ROM 用的是同一份二进制**。这判了「从源码重建模块」路线死刑，也说明「拷贝预编译模块」是官方做法而非取巧。
3. **fstab 升为「与出货构建完全一致」**：PixelOS 的 `first_stage_ramdisk/fstab.qcom` 与 LOS **逐字节相同**（8,928 B，sha256 `6a6f28e52f57…`），userdata 行 **20 个 token 零差异**。这是第 5 个独立来源，fstab 可以彻底移出候选。
4. **结论 C 有了正面参照**：PixelOS 的 `fastboot-info.txt` 明确写着 `if-wipe erase userdata` + `if-wipe erase metadata`。正常构建**必然两条都擦**；LOS/Uotan 包里没有这个文件，`-w` 只擦了 metadata。
5. **发现第三个独立缺陷**：LOS 的 `modules.load` 不只是多了 8 条幽灵，还**少了一批真实存在的本机模块**（清单差集 66 条；按实机加载状态折算，**真正会漏加载 41 个**）。
6. **修复方案从 A1 翻转为 A2**：既然两侧模块二进制本来就相同，A1 与 A2 的差别根本不是「换不换模块」，而是「用谁的清单 + 索引」——而 LOS 的清单已被证明有 58 处错误（8 幽灵 + 50 缺失），索引文件也是 A16 生成的。**推荐直接整目录替换，零手工编辑。**
7. **门禁把两者分得很干净**：PixelOS 三集合 `PASS / exit 0`；LOS 两集合 `FAIL / exit 1`（405 + 102 CRC 不符、8 + 1 悬空），LOS 的版本化目录单独 `PASS`（103/103，与 PixelOS 逐字节相同）。
8. **【09:00 实机在环，决定性】** 设备已刷 PixelOS 并接入 adb：`sys.boot_completed=1`、内核与 LOS 逐字相同、`ro.custom.version` 正是本次分析的 `-0424` 包。抽样 40 个模块 + 5 个索引文件**全部与镜像 md5 相同**；设备上 `/vendor/etc/fstab.qcom` 与 LOS **逐字节相同**（sha256 `6a6f28e52f57…`）。**所有「推断」到此升为「实测」**（§9）。
9. **两处自我更正**（均由实机数据推翻）：① 初版说缺 `qcom-cpufreq-hw`、`i2c-qcom-geni`、`phy-msm-snps-eusb2` 会导致 CPU/USB/触控异常——**实测这四个模块根本没被加载**，说法作废；② 「`dmesg` 无模块错误」只能覆盖最后约 30 秒（环形缓冲已回卷），不能当启动期证据。
10. **最有操作价值的产出**：`panic_on_oops=1` 且 `ramoops` 通道实测可用 → 下次 LOS 失败后**刷回 PixelOS 读 `/sys/fs/pstore/console-ramoops-0`** 就能拿到 panic 栈。纯 userspace hang 则留不下（`hung_task_panic=0`）。流程见 §9.7。

---

## 1. 取证对象与可信度

| 项 | 内容 |
|---|---|
| 产物 | `PixelOS_pandora-17.0-20261102-0346.zip`（OTA，5.8 GB）、`Fastboot_…-0424.zip`（6.7 GB）、单镜像 `boot/vendor_boot/dtbo/init_boot/recovery/vbmeta/super_empty.img` |
| 平台 | pandora / canoe（`android-info.txt`：`require board=pandora\|canoe`） |
| 工具 | WSL Ubuntu 24.04 的 `modinfo` / `modprobe --dump-modversions` / `mount` / `cpio`；自写 `bootimg.py`、`lz4legacy.py` 仅用于解容器格式 |
| 判据 | `module_layout` CRC（与内核 `check_version()` 同源数据格式），不依赖 vermagic 字符串 |
| **可信度边界** | PixelOS 产物**内部自洽**（三处模块全部 `6.12.69` / `0x797f2b3e`、清单 0 悬空、fstab 与 LOS 相同），这是**可启动的必要条件**。~~它是否真能在这台机器上启动，本次未验证~~ → **09:00 已由实机证实启动**（§9.1：`sys.boot_completed=1`，`ro.custom.version` 正是本次分析的 `-0424` 包）。**§1–§8 写于实机数据之前，「推断」字样保留原文，读的时候以 §9 为准。** |

---

## 2. 三处模块的字节关系（核心表）

### 2.1 PixelOS 自身：全部正确（证实）

| 位置 | `.ko` 数 | vermagic | `module_layout` CRC |
|---|---|---|---|
| `vendor_boot` ramdisk | 461 | `6.12.69-android16-6-4k` ×461 | `0x797f2b3e` ×461 |
| `vendor_dlkm` | 402 | `6.12.69-android16-6-4k` ×402 | `0x797f2b3e` ×402 |
| `system_dlkm` 版本化目录 | 103 | `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k` ×103 | `0x797f2b3e` ×103 |
| `system_dlkm/flatten` | 103 | 同上 ×103 | `0x797f2b3e` ×103 |

内核：41,511,424 字节，banner `Linux version 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k (kleaf@build-host)`——**与 LOS 的内核大小、banner 完全一致**。

### 2.2 三方同名模块的逐字节比对（证实）

| 对比 | 同名 | 逐字节相同 | 不同 |
|---|---|---|---|
| `vendor_boot`：PixelOS vs **stock** | 461 | **461** | **0** |
| `vendor_boot`：PixelOS vs LOS | 461 | 56 | **405** |
| `vendor_dlkm`：PixelOS vs **stock** | 402 | **402** | **0** |
| `vendor_dlkm`：PixelOS vs LOS | 402 | 36 | **366** |
| `system_dlkm` 版本化：PixelOS vs LOS | 103 | **103** | **0** |
| `system_dlkm/flatten`：PixelOS vs LOS | 103 | 1 | **102** |
| `system_dlkm`：PixelOS 版本化 vs PixelOS flatten | 103 | **103** | 0 |
| `system_dlkm`：LOS 版本化 vs LOS flatten | 103 | 1 | **102** |

**这张表一次性回答了三件事**：

1. **`vendor_boot` / `vendor_dlkm` 的正确模块集 = stock 的那一份 = PixelOS 的那一份**，三者是同一批二进制。LOS 的 405 / 366 个是另一个世代（A16 `6.12.23`）。
2. **LOS 的 `system_dlkm` 版本化目录完全正确**——与 PixelOS 逐字节相同。这是第二次独立确认（第一次是它自己的 103/103 CRC 全对）。
3. **LOS 的 `flatten` 副本整体是旧的**：PixelOS 的 flatten 是版本化目录的忠实副本（103/103 相同），LOS 的 flatten 只有 1 个对得上。**「flatten 应该等于版本化」这条性质在 PixelOS 上成立、在 LOS 上不成立**，可以直接当判据用。

### 2.3 五个索引文件也是同一份（证实）

| 文件 | stock md5 | PixelOS md5 | 判定 |
|---|---|---|---|
| `vendor_dlkm/lib/modules/modules.load` | `881f196656ac` | `881f196656ac` | **逐字节相同**（665 条 / 唯一 402） |
| `modules.alias` | `0a2914f9463f` | `0a2914f9463f` | 相同 |
| `modules.dep` | `82ef20528048` | `82ef20528048` | 相同 |
| `modules.softdep` | `09055562da20` | `09055562da20` | 相同 |
| `modules.blocklist` | `2e7906440f46` | `2e7906440f46` | 相同 |

`vendor_boot/lib/modules/modules.load`：stock 与 PixelOS 同为 `0a002fb07303`（172 条 / 唯一 169），LOS 为 `86dfdf3fc892`（150 条 / 唯一 147）。

**结论**：本机的模块层是一份**完整的预编译产物包**（二进制 + 索引一起发布）。任何「只换 `.ko` 不换索引」或「只换索引不换 `.ko`」的做法都会制造新的不一致——这正是 LOS 当前的形态。

---

## 3. 缺陷范围：468 个文件里只错 410 个，且错得很整齐

PixelOS 与 LOS 的 `vendor_boot` ramdisk 解包后**各 468 个文件，文件名集合完全相同**（仅 PixelOS 有：无；仅 LOS 有：无）。

| 类别 | 数量 | 相同 | 不同 |
|---|---|---|---|
| `.ko` 模块二进制 | 461 | 56 | **405** |
| `lib/modules/` 索引文件 | 5 | 0 | **5** |
| 其余（`first_stage_ramdisk/fstab.qcom`、`lib/modules/modules.load.recovery`） | 2 | **2** | **0** |

5 个不同的索引文件与体积：

| 文件 | PixelOS | LOS |
|---|---|---|
| `modules.alias` | 64,405 | 53,558 |
| `modules.dep` | 158,537 | 133,081 |
| `modules.load` | 2,665 | 2,287 |
| `modules.softdep` | 1,094 | 857 |
| `modules.blocklist` | 1,304 | 1,325 |

**这是本次事故最有价值的一条结构性事实**：LOS 的 ramdisk 骨架（fstab、recovery 清单）与一个出货构建**逐字节一致**，坏的只有模块层那 410 个文件。修复不需要碰任何配置、任何 fstab、任何 init 脚本。

---

## 4. fstab：第 5 个独立来源，逐字节相同（证实）

| 来源 | 大小 | sha256（前 12） |
|---|---|---|
| LOS `vendor/etc/fstab.qcom` | 8,928 | `6a6f28e52f57` |
| LOS `first_stage_ramdisk/fstab.qcom` | 8,928 | `6a6f28e52f57` |
| **PixelOS `first_stage_ramdisk/fstab.qcom`** | **8,928** | **`6a6f28e52f57`** |
| stock `vendor/etc` / `first_stage` | 13,814 | `391d5143…` |

userdata 行 token 级差集：**PixelOS 独有 = 无，LOS 独有 = 无，共有 20 个 token**。`/metadata` 行同样逐字节相同。

**判定**：LOS 的 fstab 与一个 AOSP 系出货构建**完全一致**，不再是「推断无差异」，而是「与出货构建同文件」。fstab 可以从候选集中彻底移出，且**修复时不要动它**。

---

## 5. `fastboot-info.txt`：结论 C 的正面参照（证实）

PixelOS Fastboot 包内该文件全文：

```
# fastboot-info for custom_pandora
version 1
flash boot
flash init_boot
flash dtbo
flash recovery
flash pvmfw
flash vendor_boot
flash --apply-vbmeta vbmeta
flash vbmeta_system
reboot fastboot
update-super
flash system
flash system_dlkm
flash system_ext
flash product
flash vendor
flash vendor_dlkm
flash odm
if-wipe erase userdata
if-wipe erase metadata
```

`android-info.txt`：`require board=pandora|canoe`。

**这升级了此前的结论**：

- 之前只能说「LOS/Uotan 包里**没有**这个文件，所以 `-w` 走了 hardcoded 回退，日志里只有 `Erasing 'metadata'`」。
- 现在有了**正面参照**：正常构建的 `if-wipe` 段**必然同时包含 `erase userdata` 与 `erase metadata`**。LOS 的 `-w` 只擦 metadata，不是「某个版本的行为差异」，而是**缺了这个文件导致的降级**。
- 同时补上一个此前未查的点：这个文件**本来该由设备树产出**（`custom_pandora` 命名说明它来自 `PRODUCT_BUILD_FASTBOOT_INFO` 之类配置）。LOS 侧缺失，属于移植时漏配，不是打包工具的问题。

---

## 6. 第三个独立缺陷：LOS 的 `modules.load` 少了一批真模块

### 6.1 `vendor_boot`（172 → 150）

| 类别 | 数量 | 明细 |
|---|---|---|
| LOS **多**出的幽灵条目（文件不存在） | 8 | `mem_object` / `qcom_tzmem` / `mi_schedule` / `metis` / `migt` / `miloadtrace` / `mi_mem_epoll` / `mi_mem_limit` |
| LOS **缺**的真模块 | 30 | 其中 **10 条是别机型**（`dispcc-chora` / `gcc-chora` / `qnoc-chora` / `tcsrcc-chora` / `videocc-chora` / `dispcc-sm4450` / `gcc-sm4450` / `pinctrl-ravelin` / `qnoc-ravelin` / `phy-qcom-ufs-qmp-v4-crow`），**20 条是 pandora 真需要的** |
| 20 条真需要的 | 20 | `bcl_soc`、`common`、`cpu_phys_log_map`、`kryo_arm64_edac`、`mem_fault_events`、`mi_extent_pool`、`mi_game`、`mi_kernel_monitor`、`mi_memory_monitor`、`mi_qmi_trace`、`mimon`、`nvmem_qfprom`、`os_cpu_qi`、`os_cpu_qs`、`perf_actuator`、`plat_common`、`powerinsight_interface`、**`qcom-cpufreq-hw`**、`rtg`、`vip_sched` |

### 6.2 `vendor_dlkm`（665 → 569）

| 类别 | 数量 | 明细 |
|---|---|---|
| LOS **多**出的幽灵条目 | 8 | `bcl_soc` / `binder_prio` / `common` / `mca_pbb` / `miwill` / `nvmem_qfprom` / `qcom_cache_allocation` / `quic`（在本分区**全部不存在**） |
| LOS **缺**的真模块 | 36 | 其中 **6 条是别机型**（`camcc-chora` / `camcc-sm4450` / `gpucc-chora` / `gpucc-sm4450` / `debugcc-chora` / `debugcc-sm4450`），**30 条是本机的** |
| 30 条本机的 | 30 | `aw882xx_dlkm`、`core_hang_detect`、`dump_binder`、`eom_driver`、`fsa4480_i2c`、**`gpi`**、**`i2c-qcom-geni`**、`mi_dma_dio`、`mi_low_lat_mem`、`mi_ntsync`、`mi_reclaim`、`miscore`、`node_cache`、`pci_phy_access`、**`phy-msm-snps-eusb2`**、`phy-msm-snps-hs`、`qcom-cpufreq-hw-debug`、`qcom-spmi-wled`、`qcom_cpuss_sleep_stats`、`qpnp-lcdb-regulator`、`rss_monitor`、`sia91xx_dlkm`、`sia91xx_tuning_dlkm`、**`spi-geni-qcom`**、`spmi-pmic-err-debug`、`task_attribute`、`wcd937x_dlkm`、`wcd937x_slave_dlkm`、`wsa885x_i2c_dlkm`、`xm_usb_pri_interface` |

### 6.3 `system_dlkm/flatten`（82 条）

| 差异 | 内容 |
|---|---|
| LOS 多 | `tls.ko` —— 内核 `# CONFIG_TLS is not set`，两侧都没有该文件，PixelOS 的 flatten 清单也不含它 |
| LOS 缺 | `exynos-hvm.ko` —— PixelOS 的 flatten 与版本化清单都有 |

### 6.4 定性（**已用实机加载状态修正**，见 §9.5）

初版按「清单差集」统计为 50 个（20 + 30）。拿到实机 `lsmod` 后修正为 **41 个**——因为 `modules.load` 是**超集**，并非每条都会真正加载：

| 分区 | LOS 缺 | 实机确实加载了 | 实机也未加载 |
|---|---|---|---|
| `vendor_boot` | 30 | **19** | 11（10 条别机型 + `qcom-cpufreq-hw`） |
| `vendor_dlkm` | 36 | **22** | 14（6 条别机型 + `i2c-qcom-geni` / `spi-geni-qcom` / `phy-msm-snps-eusb2` / `phy-msm-snps-hs` / `qpnp-lcdb-regulator` / `qcom-spmi-wled` / `qcom-cpufreq-hw-debug` / `spmi-pmic-err-debug`） |
| 合计 | 66 | **41**（去重后） | 25 |

**41 个真正会漏加载的**：`aw882xx_dlkm`、`bcl_soc`、`common`、`core_hang_detect`、`cpu_phys_log_map`、`dump_binder`、`eom_driver`、`fsa4480_i2c`、`gpi`、`kryo_arm64_edac`、`mem_fault_events`、`mi_dma_dio`、`mi_extent_pool`、`mi_game`、`mi_kernel_monitor`、`mi_low_lat_mem`、`mi_memory_monitor`、`mi_ntsync`、`mi_qmi_trace`、`mi_reclaim`、`mimon`、`miscore`、`node_cache`、`nvmem_qfprom`、`os_cpu_qi`、`os_cpu_qs`、`pci_phy_access`、`perf_actuator`、`plat_common`、`powerinsight_interface`、`qcom_cpuss_sleep_stats`、`rss_monitor`、`rtg`、`sia91xx_dlkm`、`sia91xx_tuning_dlkm`、`task_attribute`、`vip_sched`、`wcd937x_dlkm`、`wcd937x_slave_dlkm`、`wsa885x_i2c_dlkm`、`xm_usb_pri_interface`

**必须纠正初版的三处过头说法**：

1. ❌ 初版说「缺 `qcom-cpufreq-hw`（CPU 调频）会导致性能异常」→ **实测该模块根本没被加载**（cpufreq 是内建）。从影响清单中移除。
2. ❌ 初版说「缺 `i2c-qcom-geni` / `spi-geni-qcom` / `phy-msm-snps-eusb2` / `qpnp-lcdb-regulator` 会导致触控/USB/背光不工作」→ **实测这四个也都没加载**。从影响清单中移除。
3. ✅ 真正会漏的集中在三类：**小米私有监控/调度模块（`mi_*`、`mimon`、`miscore`、`rtg`、`vip_sched`、`task_attribute`、`perf_actuator`）**、**音频（`wcd937x_dlkm` / `wsa885x_i2c_dlkm` / `aw882xx_dlkm`）**、**触控与 USB-C 开关（`sia91xx_dlkm` / `fsa4480_i2c`）**。

**8 条幽灵条目的危害仍属（推断）**：实机 `modprobe -d /vendor/lib/modules <name>` 对不存在的名字返回非零（`LoadWithAliases was unable to load …`），但对**已加载**的模块同样返回非零（toybox 的 `-d` 未按预期解析文件），**因此这次实测是无效对照，不能据此断言 init 会中断**。保留原判断：会报错，是否致命未定。

**更重要的修正**：清单差集只是**第三个面**，真正更硬的是**索引文件也是旧世代的**（§9.5）。`modules.alias` / `modules.dep` / `modules.softdep` 由 A16 模块集生成，即使 `.ko` 全换对，依赖解析与 autoload 仍会错。

---

## 7. 对修复方案的影响：A1 → A2（结论翻转）

### 7.1 原来的 A1 立论已被推翻

手册原推荐 **A1（保留 LOS 的 `modules.load`，只删 8 条悬空 + 去重）**，理由是「单变量改动，A2 同时改变加载哪些模块，出问题无法归因」。

新证据使这条理由失效：

| 原假设 | 实测 |
|---|---|
| 「LOS 的清单 = stock 清单的精简版，只多了 8 条垃圾」 | ❌ LOS 的清单还**少了 50 个真模块** |
| 「A1 是单变量：只换二进制」 | ❌ A1 实际是「换二进制 + 保留一份有 58 处错误的清单」，变量没少，反而引入了一个已知错误源 |
| 「A2 会多加载 stock 的私有模块，可能带入新问题」 | ❌ PixelOS 的模块与 stock **逐字节相同**，索引文件 md5 也相同；A2 加载的就是**同一批出货二进制**，不是「stock 私有」 |

### 7.2 新推荐：整目录替换（A2 的强化版）

既然两侧模块二进制本来就相同，**根本不存在「换模块」这个动作**——存在的是「换掉一份错的清单 + 405/366 个旧二进制」。

```
$(KERNEL_PATH)/vendor_ramdisk/lib/modules/   ← 整目录替换（461 个 .ko + 5 个索引）
$(KERNEL_PATH)/vendor_dlkm/lib/modules/      ← 整目录替换（402 个 .ko + 5 个索引）
$(KERNEL_PATH)/system_dlkm_flatten/          ← 整目录替换（103 个 .ko + 索引）
$(KERNEL_PATH)/system_dlkm/                  ← 不动（与 PixelOS 逐字节相同，已正确）
```

**零手工编辑**。这消灭了「手写清单」这一整类缺陷——而这次事故的第三个缺陷正是手写清单造成的。

### 7.3 代价与残留

| 项 | 评估 |
|---|---|
| 多加载 16 个别机型模块（10 + 6） | 无匹配 DT 节点 → probe 不执行，模块驻留但不工作。stock 与 PixelOS 都这样出货且能启动（推断），代价可接受 |
| `vendor_dlkm` 清单 665 条 / 唯一 402（263 条重复） | 原厂形态，两侧一致，不是缺陷；门禁里 C3 默认 WARN |
| 文件数变化 | **零**。LOS 与 PixelOS 的 ramdisk 文件清单本来就相同（468/468），`vendor_dlkm` 的 402 个名字也相同 |

### 7.4 修复后应当出现的可验证形态

替换后，LOS 的这三处应当与 PixelOS **逐字节相同**。这是比「门禁 PASS」更强的验收判据：

```
sha256(vendor_boot/lib/modules/*.ko)  ==  PixelOS 同名文件
sha256(vendor_dlkm/lib/modules/*.ko)  ==  PixelOS 同名文件
sha256(system_dlkm/flatten/**)        ==  PixelOS 同名文件
```

---

## 8. 门禁对两侧的判定（实测）

```
PixelOS 三集合（-K boot.img）
  vb/lib/modules                  PASS   461  CRC 不符 0  悬空 0  重复 3(WARN)
  flatten/lib/modules             PASS   103  CRC 不符 0  悬空 0  重复 0
  lib/modules/6.12.69-…-4k        PASS   103  CRC 不符 0  悬空 0  重复 0
  退出码 0 —— 模块与内核 KMI 一致，可以出包

LOS 三集合
  vb/lib/modules                  FAIL   461  CRC 不符 405  悬空 8  重复 3
  flatten/lib/modules             FAIL   103  CRC 不符 102  悬空 1  重复 0
  lib/modules/6.12.69-…-4k        PASS   103  CRC 不符 0    悬空 0  重复 0
  退出码 1 —— 拒绝出包
```

**门禁第一次对着一个「已知正确」的第三方产物跑，结果与预期完全一致**——这本身是对门禁本身的验证：它不是「什么都说 FAIL」的假阳性机器，也不是「什么都说 PASS」的橡皮图章。

复跑：`MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "<_work>/wsl-pixelos-atomic.sh"`

---

## 9. 实机在环验证（2026-11-02 09:00，决定性）

设备已刷入 PixelOS 并通过 `adb`（KernelSU `su`）接入。这一节把前面所有「推断」换成了「实测」。

### 9.1 PixelOS 确实启动（证实）

```
ro.custom.version        = PixelOS_pandora-17.0-20261102-0424   ← 正是本次分析的 Fastboot 包
sys.boot_completed       = 1
uname -r                 = 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
/proc/version            = ... #1 SMP PREEMPT Tue Sep  8 15:08:49 UTC 2026
ro.build.flavor          = custom_pandora-user
ro.vendor.build.id       = CP2A.260605.016（A17）
ro.vendor.build.date     = Mon Nov  2 03:46:09 CST 2026
```

**内核字符串与 LOS 的逐字相同**，`0x797f2b3e` 由此从「按 stock 推断」升为**已实机启动验证**。方案 B/C（源码重建）也随之彻底出局。

### 9.2 来源校验：分析的镜像 = 运行的镜像（证实）

| 项 | 结果 |
|---|---|
| `vendor_dlkm` 抽样 20 个 `.ko` | **20 / 20 与镜像 md5 相同** |
| `system_dlkm` 版本化抽样 10 个 | **10 / 10 相同** |
| `system_dlkm/flatten` 抽样 10 个 | **10 / 10 相同** |
| `modules.load` / `.alias` / `.dep` / `.softdep` / `.blocklist` md5 | **5 / 5 与镜像逐字节相同**（`881f196656ac` / `0a2914f9463f` / `82ef20528048` / `09055562da20` / `2e7906440f46`） |
| `system_dlkm/flatten/modules.load` md5 | `983f77a94d8f`，与镜像相同 |

`/vendor/lib/modules` 是指向 `/vendor_dlkm/lib/modules` 的符号链接，两处是同一份内容。

### 9.3 fstab：从运行中的设备直读（证实）

设备上 `/vendor/etc/fstab.qcom` 的 sha256 = **`6a6f28e52f571132bbd66a60ff89e12a88557f662bad0ddba66c6f6635b55a09`**，与 LOS 的两份副本**完全相同**。fstab 至此有 5 个独立来源、其中 2 个来自实际启动的系统，**彻底移出候选**。

### 9.4 运行期模块状态（部分证实，有重要限定）

```
/proc/modules 行数（已加载模块）: 666
lsmod                           : 666
```

**重要限定**：`dmesg` 的环形缓冲**已回卷**——最早一行只到 `[106.238387]`，`[0.000000]` 起的启动日志已被冲掉。所以「`dmesg` 里没有任何模块加载错误」这句话**只能覆盖最后约 30 秒**，不能当作「启动期无模块错误」的证据。§8 里那条「`dmesg-module-errors.txt` 为 0 字节」的记录必须按此理解。

### 9.5 `modules.load` 是超集，不是加载清单（关键认知修正）

| 清单 | 唯一条目 | 实机确实加载 | 未加载 |
|---|---|---|---|
| PixelOS `vendor_boot`（= stock） | 169 | **99** | 70 |
| LOS `vendor_boot` | 147 | 80 | 67 |
| 设备 `vendor_dlkm`（= PixelOS/stock） | 402 | **311** | 91 |

另有 **295 个模块在两侧清单里都没有，但实机已加载**——它们靠 `modules.alias` 按需 autoload（网络协议族、文件系统等）。

**结论**：`modules.load` 的语义是「尝试加载这些」，不是「最终加载集」。因此：
- 「清单少 50 条」的严重性要按「实际会漏加载」重算 → **41 条**（见 §6.4）。
- 反过来，**`modules.alias` / `modules.dep` 的世代比清单本身更关键**：autoload 全靠它们。LOS 的这三个文件是 A16 生成的（ramdisk 内 `modules.dep` 133,081 vs PixelOS 158,537 字节），即使 `.ko` 全换对，依赖解析与 autoload 仍会错。这是**独立于 KMI 的第二个故障面**。

### 9.6 别机型模块实测不加载（支持 A2）

§6.4 里那 10 + 6 条 `chora` / `sm4450` / `ravelin` / `crow` 模块，文件在 ramdisk 里都存在、也都在厂商清单里，但**实机一个都没加载**。所以「用厂商清单会多加载别机型驱动」这个担心的实测答案是：**它们根本不会加载**，A2 无副作用。

### 9.7 失败取证方案（本次最有操作价值的一条）

设备现状：

```
/sys/fs/pstore/pmsg-ramoops-0   1785 B   ← 有内容，但不是内核日志（是 modem AT 流与零碎字符串）
console-ramoops-0               不存在   ← 说明本次启动没有 panic/oops
/proc/sys/kernel/panic_on_oops  = 1      ← 有 oops 就会 panic → 会写 console-ramoops
/proc/sys/kernel/hung_task_panic = 0     ← 纯 hang 不会 panic → 留不下任何东西
```

**因此下次刷 LOS 的取证流程**：

1. 刷 LOS → 若失败（重启循环或卡住）
2. 回到 bootloader，刷回 PixelOS 的 `boot` / `vendor_boot` / `init_boot` / `dtbo`（**不要 wipe**，`/data` 留着）
3. 启动 PixelOS，`adb shell su -c "cat /sys/fs/pstore/console-ramoops-0"`
4. 拿到 LOS 的 panic 栈——`ramoops` 是预留内存，跨重启保留

**能覆盖什么、不能覆盖什么**：

| LOS 的失败形态 | pstore 能否留下 |
|---|---|
| 内核 oops / panic（模块加载失败、probe 崩溃） | ✅ `console-ramoops-0`（`panic_on_oops=1`） |
| 硬件看门狗复位（`CONFIG_PSTORE_CONSOLE=y` 下 printk 已落盘） | ✅ 通常能留下 |
| 纯 userspace hang（init 卡死，内核无异常） | ❌ 留不下任何东西 |

这正是 build-notes §31「几秒后自动重启循环」最可能落在前两类——**所以这个方案大概率能拿到东西**。若落在第三类，需要在 cmdline 加 `hung_task_panic=1` 让它主动 panic（待验证该内核是否接受该参数）。

> ⚠️ **LOS 的 OTA 包已被删除**（`UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip` 与 `lineage-24.0-*.zip` 均不在项目根目录）。本次及此前的全部 LOS 证据现在只存在于 WSL 的 `/root/work/gstack/`（`vb/los`、`fakeout/los`、`los_*.img`）。**重刷 LOS 前需要重新构建或找回那个包**；若打算再验证一次，建议先把这些中间态导出留档。

## 10. 未取得 / 已知局限

- ~~**PixelOS 能否在 pandora 上真正启动，未验证**~~ → **已由 §9.1 证实启动**（`sys.boot_completed=1`）。此条关闭。
- **未反编译 `vendor.img` / `system.img`**。fstab 已从运行中的设备直读且与 LOS 逐字节相同（§9.3），vendor 侧无新增信息；`system.img` 的 HAL/VINTF 属运行期问题，静态不可判定。
- **未比对 `init_boot.img` 的内容**。已取到整文件 sha256 与 ramdisk 大小（PixelOS 2,564,599 / LOS 2,841,989 字节，LOS 大 277 KB），但解包格式未探明（gzip 与 lz4-legacy 两种 magic 均未命中），差值来源未查。「init 与 system 版本错配」这条候选仍未排除。**注意：两侧 init_boot 不同本身不是缺陷证据**，两个 ROM 的 init 必然不同。
- **`dtbo.img` 与 `vendor_boot` 内 `dtb` 段均已取哈希，两侧不同**（大小相同）。同样不是缺陷证据；但 BoardConfig 声称 `BOARD_PREBUILT_DTBOIMAGE` 取自 stock，该声称未与 stock 的 `dtbo` 分区比对验证。
- **设备侧 `dmesg` 的启动期日志已丢失**（环形缓冲回卷，最早只到 106 s）。要拿到完整工作态启动日志，只能在重启后立刻抓取——本次未做（避免打扰在用设备）。
- **`modprobe` 幽灵条目实测无效**：toybox 的 `-d` 对已加载模块同样返回非零，无法作为对照。
- PixelOS 的构建来源（是否官方 CI）未知；本次只把它当「一个内部自洽的第三方参照」，不当「权威基线」。
- 本次全程只读，未修改 `PixelOS_pandora-17.0-20261102/` 下任何文件、未改动设备任何分区；设备侧产物在 `/data/local/tmp/out{,2,3}`，中间态在 WSL `/root/work/pixelos/`（约 300 MB）。

---

## 11. 下一轮可以零成本继续的三件事

### 11.1 已顺手做掉的两项（结论：不同，但不构成缺陷证据）

| 项 | PixelOS | LOS | 判读 |
|---|---|---|---|
| `dtbo.img` 整文件 sha256 | `53094a7e7b943828…` | `5688f25aa58fcb52…` | 不同（同为 33,554,432 字节）。不同 ROM 的 dtbo 本就不同（overlay 与 bootargs 有差异），**不能据此判 LOS 有问题** |
| `vendor_boot` 内 `dtb` 段 sha256 | `0b1d2f5fe73c81cb…` | `27569585510fff3f…` | 大小完全相同（6,557,139），内容不同。同上，属 ROM 差异 |
| `init_boot.img` 整文件 sha256 | `23f9294a8df5f2ae…` | `c55cb7b83438cf4b…` | 不同。ramdisk 段 2,564,599 vs 2,841,989 字节，**LOS 的大 277 KB** |

**这三项都不该被当成缺陷**：dtbo / dtb / init_boot 携带的是 ROM 自己的板级覆盖与 init，两个不同发行版必然不同。要判断 LOS 是否异常，只能拿 **LOS 自己的 vendor 侧**（模块世代、fstab）作参照，而不是拿 PixelOS 的 dtbo 作基准——这一点必须写清楚，否则会重犯「症状归属错配」。

### 11.2 仍未做的三项

| 项 | 方法 | 价值 |
|---|---|---|
| `init_boot` ramdisk 逐文件比对 | 先确认压缩格式（本次 gzip/lz4 两种 magic 都没命中，需先探明），再按 §3 方法哈希 | LOS 的 ramdisk 比 PixelOS 大 277 KB，差值来源未明；若含 first-stage 模块副本，则是第四个缺陷点 |
| `dtbo` 与 stock 的比对 | 从 stock OTA 的 `payload.bin` 取 `dtbo` 分区，与 LOS 的比 | 判断 LOS 的 `BOARD_PREBUILT_DTBOIMAGE` 是否真取自 stock（BoardConfig 注释如此声称） |
| `vendor.img` 的 `build.prop` 与 `fstab` | 挂载后取 `ro.vendor.build.fingerprint` | 确认 vendor blobs 世代与模块一致（模块已确认，blobs 未确认） |
