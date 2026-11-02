# INC-PANDORA-LOS24-001 离线取证定案：内核模块 KMI 世代错配

**日期**：2026-11-01（11-02 修订：新增 §6 PixelOS 交叉验证与实机在环）
**场景**：事故响应续篇 —— 离线取证闭环。11-01 全程**不刷机、不碰设备**；11-02 为验证结论引入了同机型 PixelOS 产物作第三方基准，并在 09:00 取得实机在环数据（§6.7）。**LOS 侧仍未刷入验证。**
**参与成员**：调查员（离线取证 / 根因）、QA 与发布（矩阵 v4）、工程督导（跨源核对与汇编）
**前序文档**：`deliverables/engineering-assurance/incident-los24-bootanim-2026-11-01.md`（21 项发现、6 项阻塞、12 条行动）

---

## 📌 TL;DR

1. **当前产物存在一个致命且可离线证实的构建缺陷**：LOS 的 `vendor_boot` / `vendor_dlkm` / `system_dlkm` 里共 **873 个内核模块是按 6.12.23（android16-5）编译的**，而刷入的内核是 **6.12.69（android16-6）**。两侧 `module_layout` 的 CRC 为 `0xe976b219` vs `0x797f2b3e`，`CONFIG_MODVERSIONS=y` 下加载即被拒。
2. **`vendor_boot` 的 `modules.load` 150 条，可加载数为 0**：142 条 CRC 不符，8 条文件在 `vendor_boot` 与 `vendor_dlkm` 两处都不存在。这不是「部分模块缺失」，是**首批模块全灭**。三个分区合计悬空 **17 条**（`vendor_boot` 8 + `vendor_dlkm` 8 + `flatten` 1，§2.4）。
3. **修复要动三处，不是一处**（11-02 修订，见 §6.5）：`vendor_boot`（405 个错配）+ `vendor_dlkm`（366 个错配）+ `system_dlkm/flatten`（102 个错配），**整目录替换**。只换 `vendor_boot` 不够——second-stage 挂载 `/vendor_dlkm` 后同样加载失败。`system_dlkm` 的**版本化目录是干净的**（103/103 正确，与 PixelOS 逐字节相同），不要动。
4. **这解释了 §31 的重启循环**：`gcc-canoe.ko`（全局时钟控制器）、`clk-rpmh.ko`、`arm_smmu.ko`（IOMMU）全在不可加载之列，内核在设备探测阶段即失败 → panic → 复位循环。§27 的「卡开机动画」是 A16 blobs 构建，内核与模块世代应当一致（推断），成因不同——这正好解释了此前无法解释的「症状漂移」。
5. **推翻三条既有结论**：① 报告 §2「模块层可排除」不成立（清单一致 ≠ 内容一致，411/461 字节不同）；② build-notes §33「内核未配置 ramoops」错（`CONFIG_PSTORE_RAM=y`）；③ 「原厂加密 /data 被 LOS 未 wipe 接管」前提不成立（三份日志的 `-w` 段里根本没有 `Erasing 'userdata'` 这一行）。
6. **Tessa 的 D2 假设被否证**：两侧 userdata 行 flags 逐项相同、都含 `formattable`，唯一差异是 LOS 多 `,atgc`。
7. **结论**：🟢 缺陷可定案，且不需要任何不可逆实验；🟡 但「这是否就是历史四次失败的全部原因」需按 §2.6 的归属表区别对待。
8. **修复方案已在离线阶段验证完毕**：LOS 的 405 个 `vendor_boot` 错配模块、366 个 `vendor_dlkm` 错配模块，**每一个都有同名、CRC 正确、可直接替换的 stock 对应文件（100% 覆盖，零缺口）**。
9. **本报告自我更正两处**（均由 QA 复核提出并已采纳）：stock 多出的 28 行里 `vm-persist` 那行没有 `nofail`；「5.492 秒处理 477.25 GiB」的量纲论证过强，已降级为旁证，承重证据换成「日志里根本没有 `Erasing 'userdata'` 这一行」。
10. **执行边界（§5）**：编译、解包、模块校验一律在 WSL 的 ext4 里跑，Windows 工作区不落 `.ko` / 内核源码 / `out/`。现状有 5 个复核脚本把中间态塞进 `/tmp`（WSL 重启即丢，`wsl-crc.sh` 单独复跑会静默返回空结果），需按 §5.4 修正。
11. **【2026-11-02 新增】PixelOS 交叉验证把缺陷范围精确圈定，并推翻了修复方案选型**：同机型、同 A17 基线的 PixelOS 出货构建与 LOS 的 `vendor_boot` ramdisk **文件清单完全相同（468/468）**，其中 `first_stage_ramdisk/fstab.qcom` 与 `modules.load.recovery` **逐字节相同**；全部差异只有 **405 个 `.ko` + 5 个 `modules.*` 索引**。同时发现**第三个缺陷**：LOS 的清单除 8 条幽灵外还少了一批真模块（清单差集 66 条，**实机折算 41 个真会漏加载**）。**修复方案由 A1 翻转为「整目录替换」**（§6、行动清单第 1 条）。
12. **【11-02 09:00 实机在环】设备已刷 PixelOS 并接入 adb**：`sys.boot_completed=1`，`ro.custom.version = PixelOS_pandora-17.0-20261102-0424`（正是本次分析的包），内核与 LOS **逐字相同**；抽样 40 个 `.ko` + 5 个索引文件**全部与镜像 md5 相同**；设备上 `/vendor/etc/fstab.qcom` 与 LOS **逐字节相同**。**`0x797f2b3e` 从「按 stock 推断」升为「已实机启动验证」**（§6.7）。同时给出**失败取证方案**：`panic_on_oops=1` + ramoops 通道可用 → 下次 LOS panic 后刷回 PixelOS 读 `/sys/fs/pstore/console-ramoops-0`。

---

## 🎯 核心结论卡片

| 项目 | 内容 |
|------|------|
| Go / No-Go | 🔴 当前产物不可发布（模块全灭）；🟢 缺陷已定案，修复路径明确 |
| 严重度分布 | 🔴 5 / 🟠 6 / 🟡 3（共 14 条，含 11-02 新增 3 条） |
| 缺陷 | 内核模块 KMI 世代错配 + `modules.load` 引用缺失文件 + **清单少 41 个实机会加载的模块** + **5 个索引文件是旧世代** + **缺 `fastboot-info.txt` 导致 `-w` 不擦 userdata** |
| 关键数值 | `module_layout` CRC：模块 `0xe976b219` / 内核 `0x797f2b3e`（**已实机启动验证**） |
| 影响面 | `modules.load` 150 条 → **可加载 0 条**；三分区悬空 17 条（8 / 8 / 1） |
| 修复覆盖率 | `vendor_boot` 405/405、`vendor_dlkm` 366/366（**100%，零缺口**）；PixelOS 与 stock 的模块**逐字节相同** |
| 关键行动项 | 8 条（P0 2 / P1 3 + 1 已完成 / P2 2） |
| 不可逆操作需求 | **零**。原 E1a / E1b 全部取消 |
| 归属范围 | 高置信：§31 重启循环；不适用：§27 卡动画、§33 卡第一屏 |
| 交叉验证 | PixelOS 三集合门禁 `PASS`；其 fstab 与 LOS **逐字节相同** |
| 实机在环 | ✅ PixelOS 已启动（`boot_completed=1`），内核与 LOS 逐字相同；抽样 45 个文件 md5 全同 |

---

## 1. 各成员核心结论

### 🔧 调查员（离线取证与根因）

- 核心判断：四来源里取到三个——LOS 的 `vendor/etc/fstab.qcom` 与它自己的 `first_stage` 版**逐字节相同**（sha256 `6a6f28e5…`）；stock 的 `first_stage` 版与 LOS 的 **`fs_mgr_flags` 11 个 flag 完全一致**（含 `formattable`）；唯一差异是 LOS 挂载选项多 `,atgc`。`/metadata` 行三来源逐字节相同。
- **它关闭了四条候选**：① LOS 缺 `formattable`（否证）；② `fastboot-info.txt` 的 `if-wipe` 导致 `-w` 只擦 metadata（否证——**全仓库不存在该文件**）；③ 内核未配 ramoops（否证）；④ `atgc` 导致挂载失败（否证——内核字符串表里有独立的 `,atgc` token）。
- 关键建议：既然 LOS 的 `/data` 同样带 `formattable`，「密钥毁、密文在」在 LOS 下也应走「挂载失败 → 格式化 → 重建 → 启动」；LOS 不启动说明失败点在 `/data` late-mount **之前**，或格式化路径本身失败。嫌疑应上移到 first-stage 挂载序列、vold/KeyMint 初始化、init 与 system 的版本错配。**这个方向与 §2 的模块世代结论一致**——模块全灭时，first-stage 之后根本走不到 `/data`。

### ✅ QA 与发布（矩阵 v4）

- 核心判断：三条取证结论落地后，v3 的三个待决项全部关闭——**D3 关闭**（fstab 离线比对已完成且无差异）、**D5 裁定为「报告对、build-notes 错」**、**D6 升为矩阵第 0 步「症状归属门禁」**。删 3 条（E1b / E1a / X2），新增 2 条（E1c 真 format userdata、A1 `atgc` 单 token 消融）。
- **它推翻了我两处表述**（本报告已采纳）：① 「stock 多出的行全部带 `nofail`」不精确，`vm-persist` 那一行没有；② 「5.492 秒 / 477.25 GiB 的量纲论证」不能承重——UFS 的 erase 映射为 discard，接近瞬时，该算术只能否定写零式格式化。承重证据换成了「日志里根本没有 `Erasing 'userdata'` 这一行」。
- **它坚持了一条本报告也认同的判断**：`-w` 从未格式化 userdata，因此「在一个真正干净的 /data 上 LOS 能否启动」**本项目从未测过**，该假设是「未验证」而非「已排除」。这一点与 §2 的模块层结论**并不冲突**——两者是叠加的两个缺陷，不是替代关系。
- 关键建议：在当前证据状态下做 wipe，等于「在没有任何一条日志的情况下，用不可逆操作去猜一个已被否证了一半的假设」。E1c 有必要，但它是最后一条，不是第一条。

> 注：`qa-matrix-v4.md` 成稿于本报告 §2 的 KMI 结论落定之前，其 §9「离线已榨干、定案必须刷机」的判断基于当时的候选集。KMI 结论落地后，该判断需要修订为：**离线侧尚未榨干——模块世代这一层此前完全没被检查过**。修订见行动清单。

**修复手册（`qa-fix-runbook.md`）的三条增量判断**：

- **A1 与 A2 必须分开**。两者都换 `.ko`，差别只在「用谁的 `modules.load`」：A1 保留 LOS 的清单（清理后 `vendor_boot` 139 条 / `vendor_dlkm` 366 条），A2 换成 stock 的（169 / 402）。stock 多出来的 30 + 36 条是板级时钟与电源域（`gcc-*`、`dispcc-*`、`camcc-*`、`qnoc-*`）。**推荐 A1**：它是单变量改动；A2 同时改变「加载哪些模块」，出问题无法归因。

> **【11-02 已被推翻】** 上面这条 A1 推荐是 QA 在 KMI 定案时的判断，成立前提是「LOS 清单只是多了 8 条垃圾」。PixelOS 交叉验证证明该前提不成立：LOS 清单还**少了 66 条**（实机折算 41 个真会漏加载），且 5 个索引文件全是 A16 生成的。A1 因此不是单变量，而是「换二进制 + 保留一份错的清单 + 错的索引」。**最终推荐改为整目录替换**（§6.5、行动清单第 1 条）。保留原文是为了留下判断演化轨迹。
- **替换后与 stock 逐字节相同**：`vendor_ramdisk` 461 个、`vendor_dlkm` 402 个 `.ko` 全部一致，且文件名单 md5 不变。所以「替换」不新增也不删除任何文件，只是把同名文件换成正确世代。
- **B/C（重建内核模块）本轮不可行**：`$K` 里只有 `kernel-headers`，没有 SM8850 vendor 驱动源码；重建出的 `.ko` 其 `module_layout` CRC 由内核源码 + `.config` + 工具链共同决定，必须精确等于 `0x797f2b3e` 才可用，无源码时无法保证。留作内核升级后的长期方案。

### 🧭 工程督导（跨源核对与汇编）

- 核心判断：本次三条「新事实」全部来自**把已有产物重新读一遍**，没有一条需要设备。前一份报告分析密度很高，但它继承的排除项从未回源；一旦回源，最承重的一条（模块层）当场断裂。
- 关键建议：把「清单/摘要级证据不得用于排除」写进流程；只有哈希与 CRC 才是排除级证据。

---

## 2. 核心证据：KMI 世代错配

### 2.0 取证对象的归属（先说清楚，否则会重犯「症状归属错配」）

本次解包的是 `UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images/`，对应 `lineage-24.0-20261101-UNOFFICIAL-pandora.zip`（文件时间 11-01 **18:25**）。按 build-notes §34，这是 **18:26 那次 A17 重建的产物，从未刷入过**。

因此本节的结论分两层：

- **对当前产物：证实。** 这批镜像若有任何一次被刷入，模块必然加载失败。
- **对历史四次失败：需分开归因。** 见 §2.6。历史构建的 `vendor_boot` 未留存，无法回溯验证；但缺陷的成因（内核换新、模块未换）在 §31 之前就已存在。

这一点必须写在最前面，否则本报告会重复它所批评的那份报告的错误。

### 2.1 内核侧（证实）

从 LOS `boot.img`（100,663,296 字节）解出 kernel 段：

```
kernel_size   41,511,424
ramdisk_size  0
sha256        ed9e27aa606772d058684e023fcb2d3dca876505be90227cc8ca5e5d5b95622b
Linux version 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
```

该 sha256 与 build-notes §33 第 1 条记录的原厂 A17 内核完全一致——**内核本体确实没问题，这条排除是对的**。

### 2.2 模块侧（证实）

| 镜像 | 模块数 | 6.12.23（android16-5） | 6.12.69（android16-6） |
|---|---|---|---|
| `vendor_boot.img` ramdisk | 461 | **405** | 56 |
| `vendor_dlkm.img` | 402 | **366** | 36 |
| `system_dlkm.img` | 206 | **102** | 104 |
| **合计** | **1069** | **873** | 196 |

`system_dlkm` 那 102 个旧模块有明确的位置特征，必须写清楚，否则会误判修复范围：

| 目录 | 数量 | 世代 |
|---|---|---|
| `/lib/modules/6.12.69-android16-6-…/kernel/**` | 103 | **全部正确**（CRC `0x797f2b3e`） |
| `/flatten/lib/modules/*.ko` | 103 | **102 个旧世代** + 1 个正确 |

也就是说：`system_dlkm` 的**版本化目录是干净的**，脏的是 `flatten` 那份副本。这一条同时带来一个独立佐证——**LOS 自己的 `system_dlkm` 与 stock 的 `boot` 模块给出同一个 CRC `0x797f2b3e`，两条互不相干的路径指向同一个内核期望值**，所以该数值不依赖任何单点推断。

**修复范围因此是两处，不是一处**：`vendor_boot`（405）+ `vendor_dlkm`（366）都必须换，只换 `vendor_boot` 不够——second-stage 挂载 `/vendor_dlkm` 后同样会加载失败。**（11-02 修订：`system_dlkm/flatten` 的 102 个也是旧世代，实际是三处；见 §6.5）**

`vermagic` 原文（LOS `binder_gki.ko`）：

```
6.12.23-android16-5-gd8653a69a3aa-mi-4k SMP preempt mod_unload modversions aarch64
```

stock 同名模块：

```
6.12.69-android16-6-4k SMP preempt mod_unload modversions aarch64
```

注意 `system_dlkm` 里那 102 个旧模块的 vermagic 是 `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k`——正是 `docs/kernel-baseline.txt` 记录的 **A16 原厂内核**（OS3.0.318.0）。而 `vendor_boot` / `vendor_dlkm` 那 405 + 366 个是 `6.12.23-android16-5-gd8653a69a3aa-mi-4k`。

**两组旧 vermagic 的 git 哈希和构建 ID 都不同**（`gd8653a69a3aa-mi` / `abogki` 缺失 vs `g75e9b1c7ae7c` / `abogki463945075`），说明这是**两次不同来源的拷贝**，不是一次统一降级——`vendor_ramdisk` / `vendor_dlkm` 抄自一个自编 MI 内核树，`system_dlkm/flatten` 抄自 A16 原厂包。这也解释了为什么三处错配数量（405 / 366 / 102）互不整除、没有共同比例。

### 2.3 判据：`module_layout` CRC（证实，双源交叉）

`CONFIG_MODVERSIONS=y`（vermagic 自带 `modversions`），内核在 `check_modstruct_version()` 里对**每一个**模块无条件比对 `module_layout` 的 CRC，不一致即 `pr_err("disagrees about version of symbol")` 并返回 `-ENOEXEC`。`same_magic()` 跳过 vermagic 前缀只能绕过**版本串**比较，**绕不过 CRC**——这正是报告 §2.6 讨论过、但从未真正取数验证的那一层。

从 `.ko` 的 `__versions` 段取 `module_layout` 前 8 字节：

| 来源 | `module_layout` CRC |
|---|---|
| LOS 的 405 个旧世代模块 | `0xe976b219` |
| stock 的 461 个模块（与内核配套、实机能启动） | `0x797f2b3e` |
| LOS 自己的 `system_dlkm` 版本化目录（103 个） | **`0x797f2b3e`** |

第三行是**独立佐证**：它既不是 stock 的模块，也不是内核二进制，却给出同一个期望值。因此 `0x797f2b3e` 不依赖「stock 能启动」这一单点推断。

全量对账：**405 个不一致 / 56 个一致**，且一致的 56 个恰好是 LOS 从 stock 直接抄过来的那批（`mi_*`、`*chora*`、`*sm4450*`）。该数字由调查员独立复算，完全一致。

**真实工具复核（WSL Ubuntu 24.04，kmod 31）**——不再依赖手写正则：

```
$ modinfo -F vermagic（LOS vendor_boot 461 个 .ko）
    405 6.12.23-android16-5-gd8653a69a3aa-mi-4k SMP preempt mod_unload modversions aarch64
     56 6.12.69-android16-6-4k SMP preempt mod_unload modversions aarch64

$ modprobe --dump-modversions（全量，取 module_layout）
   LOS  : 405 × 0xe976b219 , 56 × 0x797f2b3e
   stock: 461 × 0x797f2b3e
```

两条独立工具链给出同一组数字，`modprobe` 是内核同源的 kmod 工具，其 `__versions` 解析与内核 `check_version()` 走同一份数据格式。

### 2.4 加载清单：150 条，可加载 0 条（证实）

按 LOS 自己的 `lib/modules/modules.load`（150 条）：

| 状态 | 条数 |
|---|---|
| CRC 不符（`0xe976b219` ≠ `0x797f2b3e`） | **142** |
| 文件在 ramdisk 中根本不存在 | **8** |
| **可加载** | **0** |

缺失文件不止 `vendor_boot` 这一处。三个分区合计 **17 条悬空**（门禁实测：`vendor_boot` 8 + `vendor_dlkm` 8 + `flatten` 1），按「文件到底在哪」分四类：

| 分区 | 悬空条目 | 文件实际位置 | 处置 |
|---|---|---|---|
| `vendor_boot` | `mem_object` `qcom_tzmem` `mi_schedule` `metis` `migt` `miloadtrace` `mi_mem_epoll` `mi_mem_limit`（**8**） | **两侧任何分区都没有**，`modules.dep` 也无条目 | 删。这一版构建从未产出过它们 |
| `vendor_dlkm` | `bcl_soc` `common` `nvmem_qfprom`（**3**） | 文件**在 `vendor_boot` ramdisk 里**，但两侧都不在任何 `modules.load` 中（从不加载） | 从 `vendor_dlkm` 清单删除即可，文件留着无害 |
| `vendor_dlkm` | `binder_prio` `mca_pbb` `miwill` `qcom_cache_allocation` `quic`（**5**） | **两侧任何分区都没有** | 只能删；若后续发现功能缺失，需回小米开源包核对 |
| `system_dlkm/flatten` | `tls`（**1**） | 两侧都不存在；内核 `# CONFIG_TLS is not set`（`los_kconfig.txt:1147`） | 删 |

> **计数纪律**：`vendor_boot` 的 8 条与 `vendor_dlkm` 的 8 条是**两组完全不同的名字**，不能合并成「8 条」也不能说成「9 条」。门禁按分区分别统计（8 / 8 / 1），合计 17。整目录替换后这 17 条随清单一起消失，不需要手工删。

**这些是「构建超集的残留」，不是误拼的碎片**：`modules.alias` 里仍有指向它们的别名——`alias rtnl-link-miwill miwill`、`alias of:N*T*Cqcom,qfprom nvmem_qfprom`（12 条）、`alias of:N*T*Cqcom,cache-allocation-canoe qcom_cache_allocation`（2 条）、`quic`（2 条）。说明这些驱动**在模块构建阶段存在过**，只是产物没进任何分区。删清单是对的，但要知道删掉的是什么。

> **判据纪律（一条容易踩的坑）**：不能用「`modules.dep` 里没有条目」去断定「文件不存在」。实测 `modules.dep` 只覆盖 **416/461**（`vendor_boot`）和 **374/402**（`vendor_dlkm`）——`arm_smmu.ko`、`bam_dma.ko`、`bcl_pmic5.ko` 这些货真价实且在加载清单里的模块，dep 里同样没有条目。本次结论是「dep 无条目」+「三个分区逐盘核对无文件」两条一起得到的，缺一不可。

`tls.ko` 这条还牵出一个细节：**`system_dlkm` 的 flatten 清单与版本化清单不是同一份**——两者都 82 条，但 flatten 多 `tls.ko`、版本化多 `exynos-hvm.ko`。所以改清单时必须认准是哪一个目录，不能互抄。

另有一条操作纪律：**`modules.load.recovery` 两侧逐字节相同**（7,778 B，sha256 `3b32828f…`，466 条 / 唯一 455 / 悬空 0），不需要动，也不要顺手「清理」它。

与 stock 的清单差异不是单向的：**stock 独有 30 条、LOS 独有 8 条**（30 − 8 = 22 净差）。stock 那 30 条里混着其它平台的驱动（`*chora`、`*ravelin`、`*sm4450`、`phy-qcom-ufs-qmp-v4-crow`），说明 stock 的 `modules.load` 本身是跨机型合集，**不能当作本机基线**；缺这些无害。

另需澄清一处：`ufs_qcom.ko`、`ufshcd_core.ko`、`mmc_core.ko`、`zram.ko` 在**两侧清单里都不存在**——pandora 上这些是内建（`=y`），不走 `modules.load`，不是差异点。

在不可加载之列的启动关键模块包括：

```
gcc-canoe.ko        ← 全局时钟控制器
clk-rpmh.ko         ← RPMh 时钟
clk-qcom.ko
gdsc-regulator.ko
dispcc-canoe.ko     ← 显示时钟控制器
arm_smmu.ko         ← IOMMU
qti-regmap-debugfs.ko
```

### 2.5 机制链（推断，每步有支撑）

```
gcc-canoe.ko / clk-rpmh.ko / arm_smmu.ko 等 CRC 不符 → 内核拒绝加载（-ENOEXEC）
        ↓
时钟控制器、IOMMU、显示控制器驱动缺失
        ↓
设备探测阶段大面积失败（UFS / 显示 / USB 的时钟源不存在）
        ↓
内核 panic 或关键子系统不可用
        ↓
表现为「几秒后自动重启」的循环（§31），或停在更早的启动阶段
```

**必须纠正一处**：上一版草稿曾把机制链写成「`binder_gki.ko` 加载失败 → 无 `/dev/binder` → vold / system_server 死」。**这条链是错的**——内核配置里 `CONFIG_ANDROID_BINDER_IPC=y`，binder 是**内建**的，`binder_gki.ko` 只是一个冗余/遗留模块，它加载失败不影响 `/dev/binder`。机制链已按实际时钟/IOMMU 路径重写。

**证据等级划分**：
- 「CRC 不一致」「内核版本串」「清单相同但内容不同」「150 条可加载 0 条」「8 个文件缺失」= **证实**（数值可复算）。
- 「模块缺失导致探测失败进而 panic」= **推断**。缺的是 `dmesg` 里那一行 `disagrees about version of symbol module_layout` 与随后的 probe 失败栈。

> **11-02 补充**：本节只记了「清单多 8 条幽灵」。§6.4 的 PixelOS 交叉验证发现清单还**少了 50 个真实存在的本机模块**（`vendor_boot` 20 + `vendor_dlkm` 30）。两条是独立的缺陷：幽灵条目让 `modprobe` 报错，缺失条目让对应驱动根本不加载。

### 2.6 与四次复现的对应（这里是本报告最需要克制的地方）

| 复现场景 | 症状 | 与本次缺陷的关系 |
|---|---|---|
| §27（10-27，A16 blobs + A16 GKI） | 卡开机动画 | ❌ **不适用（推断）**。那次是 A16 世代构建，内核与模块应同为 6.12.23，模块能加载；该次成因仍未定案（最可能是 A16 vendor HAL 配 A17 framework）。该构建的 `vendor_boot` 未留存，无法回溯 |
| §31（11-01 17:25，A17，13 分区） | 重启循环 | ✅ **高置信**。§32 记录当时内核已与原厂逐字节一致（即已换成 6.12.69），而模块仍来自 A16 树 → 首批模块全灭 → 探测期 panic |
| §33（11-01 17:59，双 vbmeta 全关） | 卡第一屏 160s 回落 fastboot | ❌ **不适用**。这是 bootloader 层失败，属 AVB 链自伤，另一个独立故障 |
| 18:26 之后 | 无日志 | — |

**这个归属表本身就解开了前一份报告最大的困惑**：「四次复现四种症状、失败深度递增」。原因是**每次失败的成因不同**——§27 是 blobs/框架世代错配（推断），§31 是模块世代错配（高置信），§33 是 AVB 自伤（证实）。把它们当成同一根因的四次复现，才导致「排除链」整体失效。

### 2.7 成因：半迁移（证实）

`device-trees/los24-pandora/BoardConfig.mk` 自己写明了来源：

```make
# GKI 内核 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k，
# 取自 OS4.0.5.0.XBLCNXM 的 boot.img，差异只在板级 dtbo。
...
$(call find-copy-subdir-files,*,$(KERNEL_PATH)/vendor_ramdisk/,$(TARGET_COPY_OUT_VENDOR_RAMDISK)/lib/modules) \
$(call find-copy-subdir-files,*,$(KERNEL_PATH)/system_dlkm/,$(TARGET_COPY_OUT_SYSTEM_DLKM)/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k)
```

内核二进制换成了 6.12.69，`system_dlkm` 的**目标目录名**也改成了 6.12.69，但 `$(KERNEL_PATH)/vendor_ramdisk/` 与 `vendor_dlkm/` 里的模块**没有跟着换**——目录名改了，内容没改。典型半迁移：命名对齐了，二进制没对齐。

### 2.8 修复可行性：已在离线阶段验证完毕（证实）

修复动作是「用 stock 的模块替换 LOS 的」。这件事能不能成，可以在刷机前就验证——从 stock OTA 的 `payload.bin` 解出 `vendor_dlkm` / `system_dlkm`，与 LOS 的逐一对照：

| 分区 | stock 侧模块 | CRC 分布 | 对 LOS 错配模块的替换覆盖 |
|---|---|---|---|
| `vendor_boot` ramdisk | 461 | **461 × `0x797f2b3e`** | **405 / 405（100%）** |
| `vendor_dlkm` | 402 | **402 × `0x797f2b3e`** | **366 / 366（100%）** |
| `system_dlkm` | 206（两份副本） | **206 × `0x797f2b3e`** | LOS 版本化目录本就正确，只需修 `flatten` 副本 |

也就是说：**LOS 的每一个错配模块，stock 侧都有一个同名、CRC 正确、可直接替换的对应文件，零缺口。** 替换后全量 `.ko` 的 `module_layout` CRC 均为 `0x797f2b3e`。

**并且替换不会引入任何新文件**：`vendor_dlkm` 两侧的模块名集合**完全相同**（402 vs 402，共有 402，仅 LOS 有 0，仅 stock 有 0），其中当前内容已相同的 36 个、不同的 366 个——正好是 CRC 错配的那 366 个。所以这是纯粹的「同名换内容」，不存在把 stock 私有模块带进 LOS 的风险。

**但替换完还有两处收尾工作，不做会留下残余缺陷**：

1. **17 条悬空条目**（门禁实测，按分区 8 / 8 / 1）：`vendor_boot` 8 个（`mem_object.ko`、`qcom_tzmem.ko`、`mi_schedule.ko`、`metis.ko`、`migt.ko`、`miloadtrace.ko`、`mi_mem_epoll.ko`、`mi_mem_limit.ko`）+ `vendor_dlkm` 8 个（`bcl_soc.ko`、`binder_prio.ko`、`common.ko`、`mca_pbb.ko`、`miwill.ko`、`nvmem_qfprom.ko`、`qcom_cache_allocation.ko`、`quic.ko`）+ `system_dlkm` 的 flatten 副本 1 个（`tls.ko`）——**在 LOS 与 stock 的对应镜像里都不存在**，替换后依然悬空。整目录替换会随清单一起消除（§6.5），手工路线才需要逐条删。
2. **重复条目**（这条要降级）：LOS 的 `vendor_dlkm` `modules.load` 569 条去重后 374（195 条重复）。**但 stock 侧同样有重复**——`vendor_dlkm` 665 条去重后 402（263 条重复）、`vendor_boot` 172 条去重后 169（3 条重复）。所以重复**不是 LOS 独有的缺陷**，而是这套 `modules.load` 的固有形态（同一模块按依赖顺序出现多次）。门禁因此把「重复」定为 WARN 而非阻塞项。仍然建议清一遍，因为它会让「清单条数」看起来比实际模块数多——正是本次事故里被反复误用的那种「看起来一致」。

### 2.9 门禁实测结果（构建期可直接用）

`scripts/maintain/kmi-gate.sh` 对六个集合各跑一遍，行为符合预期：

| 集合 | CRC 一致 | 条目可解析 | 结论 |
|---|---|---|---|
| LOS `vendor_boot` | 56 / 461 | 142 / 150（8 悬空） | **FAIL** |
| LOS `vendor_dlkm` | 36 / 402 | 561 / 569（8 悬空） | **FAIL** |
| LOS `system_dlkm` flatten | 1 / 103 | 81 / 82（1 悬空） | **FAIL** |
| stock `vendor_boot` | 461 / 461 | 172 / 172 | **PASS** |
| stock `vendor_dlkm` | 402 / 402 | 665 / 665 | **PASS** |
| stock `system_dlkm` flatten | 103 / 103 | 82 / 82 | **PASS** |

模拟修复后的集合（删悬空 + 去重）：`vendor_boot` 150 → 139 条，`vendor_dlkm` 569 → 366 条，`system_dlkm/flatten` 82 → 81 条。

**而且修复流程已经离线跑通**：把 `qa-fix-runbook.md` §S2–S5 的命令**逐字**在一棵临时目录树上执行（换 `.ko` + 清清单），得到 139 / 366 / 81 三个集合，门禁三项全 PASS、exit=0。也就是说，手册里的命令不是纸面推演，是执行过的。复跑：`_work/wsl-gate-runbook-check.sh`。

**最关键的一条**：门禁带 `-K <kernel>` 时能直接抓出本次事故的形态——内核 banner 校验 `PASS (6.12.69-android16-6-…)`，而模块侧 `405/461` CRC 不符。也就是说「内核换了、模块没换」这种半迁移，门禁一跑就现形，不必等到刷机失败。复跑脚本：`_work/wsl-gate-kernel.sh`。

**与既有脚本的关系（2026-11-01 已整合）**：仓库里原有的 `scripts/maintain/verify_kernel_modules.sh` 用 `strings | grep vermagic` 做判据，且只查 `system_dlkm/lib/modules` 而不查它的 `flatten` 副本——对本事故形态是**假阴性**（版本化目录确实是对的，flatten 才是脏的那份）。现已改为：`kmi-gate.sh` 是唯一实现（CRC 判据），`verify_kernel_modules.sh` 退化为薄封装，负责在 `out/` 里定位四个目录（含 flatten）并透传 `-K`。**vermagic 相同不保证 CRC 相同**，所以判据必须是 CRC。

另外 `system_dlkm` 要区分两份副本：版本化目录 `/lib/modules/6.12.69-…/` 是 103/103 正确且其 `modules.load` 用 `kernel/...` 相对路径；`flatten/` 副本是 102/103 旧世代、`modules.load` 用裸文件名。修 `flatten` 是为了消除隐患，不是修主路径。

---

## 3. 同时被证伪或澄清的旧结论

### 3.1 fstab：无差异（Tessa D2 假设被否证）

**四来源全部取到**（后两个用 WSL + 真实工具补齐，不再是推断）：

| 来源 | 提取方式 | 大小 | sha256 |
|---|---|---|---|
| LOS `vendor/etc/fstab.qcom` | `debugfs -R dump`（ext4） | 8,928 B | `6a6f28e5…` |
| LOS `first_stage_ramdisk/fstab.qcom` | vendor_boot v4 → LZ4 legacy → cpio | 8,928 B | `6a6f28e5…` |
| stock `vendor/etc/fstab.qcom` | `mount -t erofs`（EROFS，LZ4_0PADDING） | 13,814 B | `391d5143…` |
| stock `first_stage_ramdisk/fstab.qcom` | payload → vendor_boot → LZ4 → cpio | 13,814 B | `391d5143…` |

**每侧两份副本逐字节相同**——这证实了调查员此前只能推断的那一点：stock 的 `vendor/etc` 与 `first_stage` 是同一份文件。

整条结论可以用一条命令重算，输出只有一行：

```bash
wsl -d Ubuntu-24.04 -u root -- bash "$W/wsl-fstab4.sh"
# token 级差集（按空格与逗号切分）
# -- 只在 stock 有 --      （空）
# -- 只在 LOS 有 --   atgc
```

| 项 | LOS | stock |
|---|---|---|
| userdata 行 flags | `latemount,wait,check,formattable,fileencryption=…,keydirectory=…,metadata_encryption=…,quota,reservedsize=128M,sysfs_path=…,checkpoint=fs` | **逐项相同** |
| 唯一差异 | 挂载选项多 `,atgc`（f2fs active GC，性能项） | — |
| `/metadata` 行 | `f2fs noatime,nosuid,nodev,discard wait,check,formattable,first_stage_mount` | **逐字节相同** |
| stock 多出条目 | — | `mi_ext`、24 条 `overlay`、`vm-persist`、`rescue`，共 28 行 / 26 个挂载点 |

**结论**：两侧 userdata 行**都含 `formattable`**。「stock 会重建 / LOS 不会」不成立，E1b 的主要立论依据消失。

**一处自我更正（由 QA 复核提出）**：不能写「stock 多出的行全部带 `nofail`」。实测 28 行里 **27 行带 `nofail`，1 行不带**——`/dev/block/bootdevice/by-name/vm-persist /mnt/vendor/vm-persist ext4 … wait`（只有 `wait`，无 `check`、无 `nofail`）。方向不变（LOS 少挂载一个分区只会少一个挂载点，不会导致挂载失败），但台账必须按 27/28 写，否则执行者会误以为这 28 行都有兜底。

**附带更正**：报告 §4.2 / §4.6 把 `/metadata` 写作 `ext4`，实际两侧都是 **f2fs**。

### 3.2 `CONFIG_PSTORE_RAM=y`（build-notes §33 是错的）

从 `IKCFG_ST` 段解出的内核配置：

```
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_DEFAULT_KMSG_BYTES=10240
# CONFIG_PSTORE_BLK is not set
CONFIG_ANDROID_BINDER_IPC=y          ← 顺带澄清：binder 内建
```

12 份 dtb（`device-trees/pandora-dt/original/base-parts/*.dtb`）全部含 `ramoops` / `ramoops-region` 节点名。

**结论**：ramoops 链路完整，build-notes §33「内核未配置 ramoops」是误判。但 **pstore 为空仍然判别力很低**——它只在内核 `kmsg_dump`（panic/oops）时落盘，userspace hang 与 PMIC/watchdog 静默复位都不留 dump。

### 3.3 `fastboot -w` 从未碰 userdata（结构级证据）

`docs/fastboot-getvar-all.txt`（10-27 14:55，比刷机早 3 分钟、同一次会话）：

```
partition-type:userdata:f2fs
partition-type:metadata:raw
partition-size:userdata: 0x77501FB000   → 477.25 GiB
partition-size:metadata: 0x4000000      → 64 MiB
```

三份刷机日志的 `-w` 段：`Erasing 'metadata' OKAY [4.020s]` → `Finished. Total time: 5.492s`。

**承重证据（结构事实，不依赖吞吐）**：

1. 三份日志的 `-w` 段**只有一条** `Erasing 'metadata'`，**没有任何 `Erasing 'userdata'` 行**。fastboot 的 `-w` 对每个待处理分区都会打印一行 `Erasing '<name>'`。
2. 紧随其后的 `Erase successful, but not automatically formatting. / File system type raw not supported.` 是**成对输出**——fastboot 对每个分区是「erase 一行 + 紧跟一段 format 结果」。本日志里成对的只有 metadata 一组。
3. 「`raw`」归属 **metadata**：同一份 getvar 显示 metadata 声明类型就是 `raw`，userdata 是 `f2fs`（若 fastboot 处理的是 userdata，会打印 `f2fs not supported` 而不是 `raw`）。

**一处自我更正（由 QA 复核提出）**：初稿曾用「5.492 秒处理 477.25 GiB 需 86.9 GiB/s，物理上不可能」作承重论证。**这个论证过强，已降级为旁证**——UFS 上的 erase 通常映射为 discard/unmap，接近瞬时，该算术只能否定「逐字节写零式格式化」，否定不了「erase 指令本身」。结论不变，但承重证据换成了上面三条结构事实。

**连带更正**：build-notes §31「data 加密不兼容 ← 刷前已 `-w` → 排除」依据不成立，退回「未验证」；§27「清 data 后仍卡住」是**实验未执行（S0）**，不是阴性结果。

### 3.4 `fastboot-info.txt` 全仓库不存在（关闭前一份报告的「待验证」项）

前一份报告把它列为待验证：「`-w` 是否**必然**擦 metadata 并无 AOSP 层保证，实际擦哪个分区由 `fastboot-info.txt` 的 `if-wipe` 指令决定」。

实测遍历：LOS OTA zip 内、stock OTA zip 内、`UotanToolbox_…/` 目录、`sysonly/`、`scripts/` —— **全部不存在 `fastboot-info.txt`**。而 fastboot 二进制里内置了回退逻辑（"Flashing from hardcoded images. fastboot-info.txt is empty or does not exist"）→ 走硬编码回退，`-w` 仍执行内置的 `erase metadata`。

**结论**：`if-wipe` 这条路不存在，`-w` 擦 metadata 是内置行为，与本机构建产物无关。该「待验证」项关闭。

**【11-02 补充，结论收窄】PixelOS 提供了正面参照**：其 Fastboot 包内的 `fastboot-info.txt` 明确写着 `if-wipe erase userdata` + `if-wipe erase metadata`（全文见交叉验证报告 §5）。这说明**正常构建必然两条都擦**；LOS/Uotan 包里缺这个文件属于移植时漏配——该文件本应由设备树通过 `PRODUCT_BUILD_FASTBOOT_INFO` 一类配置产出（包内 `custom_pandora` 的命名即由此而来），不是打包工具的问题。

所以上面那句「与本机构建产物无关」要收窄：`-w` 擦 metadata 确实是 fastboot 的硬编码回退行为，但**「只擦 metadata」这个降级结果本身就是 LOS 的构建缺陷**（见 §4 第 13 条）。这也顺带解释了为什么三份刷机日志里都没有 `Erasing 'userdata'`——不是 fastboot 挑了 metadata，是这个包根本没告诉它要擦 userdata。

### 3.5 ramoops 的 DT 侧细节（补充）

12 份 dtb 全部含 `ramoops-region` 节点，且 **12/12 均无 `ecc-size` 属性**——前一份报告「ramoops 无 ECC」的说法**属实**。这也意味着：一旦发生冷复位（长按电源），DDR 内容不保证保留，取证窗口极窄。

顺带纠正一处命名：mainline 内核没有 `CONFIG_PSTORE_RAMOOPS` 这个符号，正确名字是 `CONFIG_PSTORE_RAM`（本机为 `=y`）。

---

## 4. 综合发现（按严重度）

| # | 严重度 | 类别 | 定位 | 问题 | 建议 | 来源 |
|---|---|---|---|---|---|---|
| 1 | 🔴 | 构建缺陷 | `vendor_boot` / `vendor_dlkm` / `system_dlkm` | 873 个模块按 6.12.23 编译，装入 6.12.69 内核；`module_layout` CRC `0xe976b219` ≠ `0x797f2b3e` | 全量替换为 6.12.69 世代模块，或按 6.12.69 源码重建 | 调查员 / 督导 |
| 2 | 🔴 | 构建缺陷 | `vendor_boot` 的 `modules.load` | 150 条中 8 条指向 ramdisk 里不存在的文件；连同 CRC 不符共 150/150 不可加载 | 校验 `modules.load` 每条都能在镜像内找到文件 | 督导 |
| 3 | 🔴 | 证据降级 | build-notes §33 第 3 条、报告 §2.8 | 「清单完全一致 ⇒ 排除」把文件名集合当成内容一致；实测 411/461 内容不同 | 「清单一致」不得作为排除依据；排除级证据须为哈希或 CRC | 调查员 |
| 4 | 🔴 | 前提错误 | 报告 §4.3 / 结论 | 「原厂加密 /data 被 LOS 未 wipe 接管」不成立：`-w` 只擦 metadata，userdata 从未被格式化（477.25 GiB / 5.492s） | 时间线整段重写；`-w` 假成功升为工具级反面证据 | 督导 |
| 5 | 🟠 | 机制误判 | build-notes §33 | 「内核未配置 ramoops」与 `CONFIG_PSTORE_RAM=y` 直接冲突 | 改为「ramoops 已配置，但只捕获 panic，静默复位不留 dump」 | 调查员 / 督导 |
| 6 | 🟠 | 假设失效 | Tessa v3 D2 | 「stock 有 formattable / LOS 没有」不成立，两侧逐项相同 | D2 关闭；E1b 依据消失 | 督导 |
| 7 | 🟠 | 构建流程 | `los24-pandora/BoardConfig.mk` | 内核与模块来自不同世代，`system_dlkm` 目标目录名已改而 `vendor_ramdisk` / `vendor_dlkm` 未换 | 增加「内核版本 ↔ 模块 vermagic 一致性」构建期门禁 | 督导 |
| 8 | 🟠 | 归因错误 | 前序报告全篇 | 把三种不同成因的失败当作同一根因的四次复现，导致排除链整体失效 | 每个症状单独立案，见 §2.6 归属表 | 督导 |
| 9 | 🟡 | 文档笔误 | 报告 §4.2 / §4.6 | `/metadata` 写作 ext4，实际两侧均为 f2fs | 更正 | 督导 |
| 10 | 🟡 | 计数漂移 | build-notes §33 第 3 条 | 记「468 文件」，实测 472 文件（461 `.ko`） | 以实测为准 | 调查员 |
| 11 | 🟡 | 判据缺失 | 报告 §2.6 | 讨论了 CRC 先于 vermagic，但从未取过 CRC 数值 | 补取数步骤作为模板 | 督导 |
| 12 | 🔴 | 构建缺陷 | `vendor_boot` / `vendor_dlkm` 的 5 个 `modules.*` 索引 | `modules.alias` / `.dep` / `.load` / `.softdep` / `.blocklist` 全部由 A16 模块集生成；autoload 完全依赖它们，`.ko` 换对也白搭（§6.4） | 整目录替换，索引与二进制一起换（§6.5） | 交叉验证 |
| 13 | 🟠 | 构建缺陷 | `modules.load`（三个分区） | 除 17 条悬空外，还**少 41 个实机会加载的模块**（清单差集 66，按 `lsmod` 折算）；缺的是小米私有调度、音频、触控/USB-C 开关（§6.4） | 同第 12 条，整目录替换 | 交叉验证 |
| 14 | 🟠 | 构建流程 | 设备树的 fastboot-info 配置 | 缺 `fastboot-info.txt` → `-w` 走硬编码回退，只擦 metadata 不擦 userdata（§3.4） | 补 `PRODUCT_BUILD_FASTBOOT_INFO` 一类配置，使 `if-wipe` 段包含 `erase userdata` | 交叉验证 |

**做得好的地方**：§33 第 1 条（内核 sha256）与第 2 条（boot.img 结构）经复核完全成立；报告 §2.5 的 fstab 三级查找机制表述准确；「不可逆操作排最后」「warm reset 收尾」两条纪律在全过程中被真正执行。

---

## 5. 执行边界与取证工作流

> 前半（5.0–5.5）是「哪些必须在 WSL 里跑」；后半（5.6–5.8）是「在 WSL 里具体怎么取」。

### 5.0 规则

**Windows 侧只做「调度 + 收证据」，不做「编译 + 解包」。**

- 凡是会产生 `.ko`、内核源码树、`out/`、镜像展开目录的操作，一律在 WSL 的 ext4 文件系统内执行，产物也只留在那里。
- Windows 工作区（`C:\Users\MSI\Desktop\HB\1\2\2\lineage os`）只接收**小体量、不可再生、有取证价值**的文本与哈希。
- 判定标准不是文件大小，而是**能不能从现有输入重新算出来**：能重算的（解包结果、模块集、构建产物）留在 WSL；不能重算的（刷机日志、getvar、sha256、CRC 分布）回写 Windows。

这条规则不是洁癖。本次事故的 P0 缺陷就是「旧世代模块混进新内核」，而 `scripts/maintain/clean_stale_modules.sh` 这个脚本存在的全部理由，就是清理 `out/target/product/pandora` 下混入的 A16 残留——**构建产物一旦在共享目录里反复落盘，旧世代的 `.ko` 就会以「上次留下的那份」的形式存活下来**。把产物关在 WSL 的单一位置，是这条 P0 门禁的前置条件。

### 5.1 必须在 WSL 内执行（Windows 侧不得产生任何文件）

| 类别 | 具体内容 | WSL 内位置 | 不能放 Windows 的理由 |
|---|---|---|---|
| 源码树同步 | `repo init` / `repo sync`，LOS 24.0（1400 项目 / 409 GB）、TWRP 16.0 | `/root/los24`、`/root/android/lineage` | 409 GB 走 `/mnt/c` 的 9p 协议不可行；`repo`/`git` 需要可执行位与大小写敏感 |
| 全量编译 | `make` / `m`，产出 `out/target/product/pandora/**` | 同上 `out/` | `out/` 数十万文件；`.ko` 单次产出 1069 个；Windows 实时扫描会拖慢并锁文件 |
| 内核处理 | A17 内核解包、dtb 拆分、`mkbootimg` / `lpmake` 打包 | `/root/a17kernel`、`/root/pandora-kernel-staging`、`out/host/linux-x86/bin/` | 需要 Linux 二进制工具链；`kernel-headers` 是符号链接树 |
| 镜像解包取证 | `debugfs`、`mount -t erofs`、`cpio`、`lz4` 解 vendor_boot / vendor_dlkm / system_dlkm | `/tmp/verify`、`/tmp/vb`、`/tmp/mnt`（**应改为 §5.4 的持久目录**） | 单次解包 461 个 `.ko`；`mount -o loop` 需要 root 与 loop 设备，Windows 侧没有 |
| 模块校验 | `modinfo -F vermagic`、`modprobe --dump-modversions`、`strings` 扫 `6.12.23` / `6.12.69` | 同上 | kmod 工具只存在于 Linux；这是本次全部关键数值的来源 |
| OTA / super 拼装 | `payload_dump.py` 之后的分区重组、`lpmake` / `lpdump` | `/root/stage`、`/root/os405` | 单分区 589 MB 级，落 Windows 只增体积不增信息 |

### 5.2 允许并应当回写 Windows 工作区

| 内容 | 落点 | 体积量级 |
|---|---|---|
| 本报告与各成员产出 | `deliverables/gstack/`、`_member/` | 数十 KB |
| 文本类一手证据 | `_work/fstab-qcom-*.txt`、`los_kconfig.txt`、`docs/*.txt`、`docs/logs/` | 单文件 ≤ 224 KB |
| 哈希与统计结果 | sha256、CRC 分布、`modules.load` 对账表 | 数 KB |
| 脚本与设备树 | `scripts/`、`device-trees/`、`tools/*.py` | 源码，本就在 Windows |
| 刷机动作 | `platform-tools/fastboot.exe` / `adb.exe` | 设备由 Windows 侧持有（见 `docs/wsl-adb-guide.md` 方案 A） |

`tools/` 与 `_work/` 里那几个纯 Python 只读解析器（`ext4mini.py` / `erofsmini.py` / `cpiomini.py` / `lz4legacy.py` / `bootimg.py`）是例外：它们无第三方依赖，Windows 侧直接跑，输出只有文本——这类「在 Windows 跑、只吐文本」的脚本不违反边界。

### 5.3 为什么不能反过来

| 障碍 | 具体表现 |
|---|---|
| 协议开销 | `/mnt/c` 每次文件操作都要跨 VM 边界；`repo sync` 的百万级小文件在这种路径上不可行 |
| 元数据缺失 | DrvFs 默认不保留可执行位与符号链接，`make`、`git`、`repo` 会误判文件状态 |
| 文件数 | 一次 ramdisk 解包 461 个 `.ko`、`out/` 数十万文件；Windows 侧杀软实时扫描叠加，构建时间与失败率同时上升 |
| 世代污染 | 产物落在共享目录后，旧世代 `.ko` 会以「上次留下的」形式存活——正是 `clean_stale_modules.sh` 要清理的那类残留 |
| 备份与提交噪音 | `.gitignore` 已拦 `*.ko` / `*.img` / `*.bin` / `out/`，但只拦得住提交，拦不住落盘 |

### 5.4 现状偏差（实测，已整改）

规则是这次才写死的，立规时现有脚本还没完全遵守。逐项核对与整改记录如下（表格是**立规当时**的状态，整改见本节末）。

| 脚本 | 现状 | 问题 |
|---|---|---|
| `_work/wsl-fstab4.sh` | `OUT=/tmp/verify` | WSL 空闲重启后 `/tmp` 清空 |
| `_work/wsl-modinfo.sh` | `OUT=/tmp/verify` | 同上；它是 `wsl-crc.sh` 的上游 |
| `_work/wsl-crc.sh` | 读 `/tmp/verify/los_vb`，**自己不重新解包** | **单独复跑会静默返回空结果**——`find` 找不到目录，输出 0 行，看起来像「没有模块」，比报错更危险 |
| `_work/wsl-cover-vb.sh` | `O=/tmp/vb`，自解包 | 可独立跑，但结果不持久 |
| `_work/wsl-gap.sh` | `/tmp/mnt`，且依赖 `/tmp/verify/los_vb` | 同时踩上面两条 |

`_work/README.md` 的原文是「所有产物必须落在本目录（Windows 路径），不要在 `/tmp` 里存中间态」。**意图对，落点错**：它防的是 `/tmp` 易失，但把 461 个 `.ko` 的解包结果塞回 Windows，正好违反 §5.1。

**裁定**：

- 中间态（解包树、`.ko` 集合、`mount` 点）→ `/root/work/gstack/`（WSL ext4，持久，不进 `/tmp`，不进 `/mnt/c`）。
- 证据（fstab 文本、sha256、CRC 分布、对账表）→ `deliverables/gstack/_work/`。
- 每个 `wsl-*.sh` 开头加一步 `[ -d "$STAGE" ] || exit 9` 的存在性断言，杜绝「静默 0 行」。

**整改已落地（2026-11-01 21:55）**：

| 项 | 处理 |
|---|---|
| 公共前置 | 新增 `_work/wsl-common.sh`：统一 `STAGE`/`WORK`/`IMGS`，提供 `need()` 断言、`ensure_ramdisks`、`ensure_stock_dlkm_mount`、`crc_of` |
| stage 初始化 | 新增 `_work/wsl-stage-init.sh`：从 payload 提取 `vendor_boot`/`vendor_dlkm`/`system_dlkm`、解两侧 ramdisk 到 `$STAGE/vb/`。实测空目录到就绪约 1 分钟、373 MB；`vendor`（589 MB）默认不提取 |
| 脚本自包含 | `wsl-crc.sh`、`wsl-modinfo.sh`、`wsl-cover-vb.sh`、`wsl-fstab4.sh` 改为 `source wsl-common.sh` + 自动 `ensure_ramdisks`，**单独复跑不再返回空结果**；缺 stage 会 `FATAL` + exit 9 |
| 门禁判定 | `wsl-crc.sh` 与 `wsl-cover-vb.sh` 增加 PASS/FAIL 与非零退出码，可直接进 CI |
| 体积 | `_work/` 从 911 MB 降到 **约 1.5 MB**（仅剩脚本与文本证据）；中间态全部迁到 `$STAGE` |

复跑验证（清空 `$STAGE` 后单跑 `wsl-crc.sh`）已通过：自动提取三个分区 → 解两侧 ramdisk → 输出 `405 × 0xe976b219 / 56 × 0x797f2b3e`，判定 `FAIL`（符合预期）。

### 5.5 一处顺带发现的隐患

`.gitignore` 第 37 行的 `*.ko` 是通配，把 recovery 预置的两个模块也一起忽略了：

```
device-trees/los-pandora/device-pandora/recovery/root/vendor/lib/modules/1.1/exfat.ko
device-trees/twrp-pandora/device/xiaomi/pandora/recovery/root/vendor/lib/modules/1.1/exfat.ko
```

`git check-ignore -v` 确认命中 `.gitignore:37`，`git ls-files "*.ko"` 返回 0 条——**这两个文件当前不在版本库里**。它们不是构建产物，是 recovery 挂载 exFAT 的预置模块，重新 clone 后会缺失。

修法：在 `*.ko` 之后加白名单，不要放宽通配本身。

```gitignore
*.ko
!device-trees/*/*/recovery/root/vendor/lib/modules/**/*.ko
```

---

### 5.6 取证对象 → 工具对照

本次一半以上的证据是「把已有产物重新读一遍」得到的，读的工具决定可信度。原则：**能在 WSL 里用内核同源工具算的，不要用手写解析器算；手写解析器只用来做交叉验证。**

| 对象 | 格式 | 工具 | 备注 |
|---|---|---|---|
| `vendor.img`（LOS） | ext4 | `debugfs -R "dump /etc/fstab.qcom <out>"` | 最省事，一条命令 |
| `vendor.img`（stock） | EROFS + LZ4 | `mount -t erofs -o loop,ro` | **`dump.erofs` 版本太老没有 `--cat`**，`fsck.erofs` 只能整盘 `--extract`，挂载才是正解 |
| `vendor_boot.img` | boot header v4 | `bootimg.py` 解头 → `lz4legacy.py` 解 LZ4 legacy frame → `cpio -idm` | LZ4 magic `0x184C2102`，不是标准 frame |
| `.ko` 的 vermagic | ELF | `modinfo -F vermagic` | 比 grep `vermagic=` 可靠 |
| `.ko` 的 CRC | `__versions` 段 | `modprobe --dump-modversions <ko> \| grep module_layout` | 与内核 `check_version()` 同源数据格式 |
| OTA 分区 | `payload.bin` | `wsl_extract_part.py`（zip 内 STORED，裸偏移 5173） | 只解需要的分区，不碰 9 GB |

### 5.7 踩坑记录（都是实际卡过的）

1. **WSL 重启会清 `/tmp`，但 `/root` 是持久的。** 第一次把 `stock_vendor_dlkm.img` 解到 `/tmp`，隔一条命令再挂载就 `failed to setup loop device`——文件已经没了。后来做了决定性实验：`echo marker > /root/work/gstack/PERSIST_TEST` → `wsl --terminate Ubuntu-24.04` → 重启后 `PERSIST_TEST` 仍在，而 `/tmp/mnt` 已消失。**结论：中间态放 `/root/work/gstack/`（跨重启持久），不要放 `/tmp`。**
2. **Git Bash 调 `wsl.exe` 必须加 `MSYS_NO_PATHCONV=1`。** 否则 `/mnt/c/...` 会被改写成 `C:/...`，WSL 里找不到文件。
3. **`$VAR` 会被外层 shell 提前展开。** `wsl -- bash -c 'echo $PATH'` 打印出来的是 Windows 的 PATH。结论：把脚本写成 `.sh` 文件再 `wsl bash <path>` 执行，不要拼 `bash -c`。
4. **`dump.erofs` 版本过老。** 该版本没有 `--cat` / `--extract`，只能 `-S` / `--ls` / `--path`。读单个文件要靠 `mount -t erofs`，或 `fsck.erofs --extract`（整盘解，589 MB 镜像不划算）。
5. **不要把手写解析器的结果当结论。** 本次 Python 正则取的 CRC 与 `modprobe --dump-modversions` 完全一致，但这属于「事后验证通过」，不是「一开始就可信」。凡是要写进报告的数值，都应有第二工具链复核。
6. **脚本之间的隐式依赖会制造「静默 0 行」。** `wsl-crc.sh` 原本读的是 `wsl-modinfo.sh` 留在 `/tmp/verify` 的产物，单独复跑时 `find` 找不到目录、输出 0 行，看起来像「没有模块」——比报错更危险。已在 §5.4 整改：所有脚本 `source wsl-common.sh`，缺 stage 时自动初始化，仍缺则 `FATAL` + exit 9。

### 5.8 复跑入口

```bash
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"

# 0) 一次性准备（幂等；空目录到就绪约 1 分钟）
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-stage-init.sh"

# 1) 四来源 fstab（需要 stock vendor.img，首次会多花 1–2 分钟提取 589 MB）
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-fstab4.sh"

# 2) 模块世代与替换覆盖率（带 PASS/FAIL 与非零退出码）
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-crc.sh"
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-cover-vb.sh"

# 3) 构建期门禁（判据是 CRC，不是 vermagic 字符串）
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- \
  bash "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/verify_kernel_modules.sh" \
  --out /root/work/gstack/fakeout/los/target/product/pandora -q
```

产物清单与再生方式见 `deliverables/gstack/_work/README.md`。

---

## 6. PixelOS 交叉验证（2026-11-02 新增）

**完整报告**：`deliverables/gstack/pixelos-cross-reference-2026-11-02.md`

拿到同机型、同 A17 基线、已构建的 PixelOS 产物（`PixelOS_pandora-17.0-20261102/`）后，把 §2 的结论做了一次第三方交叉验证。三条结论被强化，一条被推翻。

### 6.1 缺陷范围被精确圈定（证实）

PixelOS 与 LOS 的 `vendor_boot` ramdisk 解包后**各 468 个文件，文件名集合完全相同**。差异只有：

| 类别 | 数量 | 相同 | 不同 |
|---|---|---|---|
| `.ko` 模块二进制 | 461 | 56 | **405** |
| `lib/modules/` 索引（alias/dep/load/softdep/blocklist） | 5 | 0 | **5** |
| `first_stage_ramdisk/fstab.qcom`、`modules.load.recovery` | 2 | **2** | **0** |

**含义**：LOS 的 ramdisk 骨架（fstab、recovery 清单）与一个出货构建**逐字节一致**，坏的只有模块层那 410 个文件。修复不需要碰任何配置、fstab、init 脚本——这比原报告「要动两处」更精确。

### 6.2 本机模块是固定的预编译产物（证实）

| 对比 | 结果 |
|---|---|
| `vendor_boot`：PixelOS vs stock | **461 / 461 逐字节相同** |
| `vendor_dlkm`：PixelOS vs stock | **402 / 402 逐字节相同** |
| 五个 `modules.*` 索引 md5 | stock 与 PixelOS **完全一致**（`modules.load` 同为 `881f196656ac`，665 条） |

**含义**：两个互不相干的 ROM 用的是**同一份模块二进制**。所以「从源码重建模块」（方案 B/C）不是「本轮不可行」，而是**这个设备上根本不存在这条路**——模块是随 vendor blobs 一起发布的。同时「拷贝预编译模块」不是取巧，是官方做法。

### 6.3 fstab 升为「与出货构建同文件」（证实）

PixelOS 的 `first_stage_ramdisk/fstab.qcom` 与 LOS **逐字节相同**（8,928 B，sha256 `6a6f28e52f57…`），userdata 行 **20 个 token 零差异**。这是第 5 个独立来源。§3.1 的结论由「推断无差异」升为「与出货构建完全一致」。

### 6.4 第三个缺陷：清单少了一批真模块（证实，已按实机加载状态折算）

原报告只记了「多 8 条幽灵」。实测 LOS 的清单还**少了 66 条**（清单差集）；按实机 `lsmod` 折算，**真正会漏加载的是 41 个**：

| 分区 | 幽灵（多） | 别机型（实测不加载，可忽略） | 差集 | **实机确实加载（真缺陷）** |
|---|---|---|---|---|
| `vendor_boot` | 8 | 10 | 30 | **19** |
| `vendor_dlkm` | 8 | 6 | 36 | **22** |
| 合计 | 16 | 16 | 66 | **41**（去重后） |

**41 个真正会漏加载的**集中在三类：小米私有监控/调度（`mi_*`、`mimon`、`miscore`、`rtg`、`vip_sched`、`task_attribute`、`perf_actuator`）、音频（`wcd937x_dlkm` / `wsa885x_i2c_dlkm` / `aw882xx_dlkm`）、触控与 USB-C 开关（`sia91xx_dlkm` / `fsa4480_i2c`）。缺它们的后果是**相应外设不工作**；是否阻止开机属（推断）。

**两处必须纠正**（实机数据推翻）：

1. `qcom-cpufreq-hw`、`i2c-qcom-geni`、`spi-geni-qcom`、`phy-msm-snps-eusb2`、`qpnp-lcdb-regulator` —— 这五个**实测在设备上都没被加载**，初版把它们列为「CPU 调频 / 总线 / USB / 背光必需」是错的，已从影响清单移除。
2. **`modules.load` 是超集**：`vendor_boot` 清单 169 唯一里只有 99 实际加载，`vendor_dlkm` 402 唯一里只有 311。另有 295 个模块不在任何清单里却被 autoload。所以「清单差集」不能直接等同于「运行时差异」，必须用 `lsmod` 折算。

**比清单更硬的是索引文件**：`modules.alias` / `modules.dep` / `modules.softdep` 也全是 A16 生成的（ramdisk 内 `modules.dep` 133,081 vs PixelOS 158,537 字节）。autoload 完全依赖它们，**即使 `.ko` 全换对，依赖解析与按需加载仍会错**。这是独立于 KMI 的第二个故障面，也是「整目录替换」优于「只换 .ko」的核心原因。

### 6.5 修复方案选型翻转：A1 → 整目录替换（本报告修订）

手册原推荐 A1（只换 `.ko`、保留 LOS 清单并删 8 条），理由是「单变量改动」。该理由已被推翻：

- LOS 的清单不是「stock 清单的精简版」，而是**少了 66 条（实机折算 41 个真会漏加载）+ 多了 8 条幽灵**。A1 等于「换二进制 + 保留一份有错误的清单」。
- **更关键：5 个索引文件（`modules.alias` / `.dep` / `.load` / `.softdep` / `.blocklist`）也是 A16 生成的**。A1 保留它们，等于把「依赖解析表」和「autoload 别名表」留在旧世代——`.ko` 换对了也白搭。
- A2 所谓「会带入 stock 私有模块」也不成立——两侧模块二进制**逐字节相同**，A2 加载的就是同一批出货二进制。

**新推荐**：三处**整目录替换**（`vendor_ramdisk/lib/modules/`、`vendor_dlkm/lib/modules/`、`system_dlkm_flatten/`），`system_dlkm/` 版本化目录**不动**（与 PixelOS 逐字节相同）。**零手工编辑**，一次消灭「手写清单」和「陈旧索引」两类缺陷。

**更强的验收判据**（替代「门禁 PASS」）：替换后 LOS 的这三处应与 PixelOS **逐字节相同**。

### 6.6 门禁首次对着第三方正确产物实测（证实）

```
PixelOS 三集合   PASS / exit 0   （461 + 103 + 103，CRC 不符 0、悬空 0）
LOS    三集合   FAIL / exit 1   （405 + 102 CRC 不符、8 + 1 悬空）
LOS 版本化目录   PASS           （103/103，与 PixelOS 逐字节相同）
```

这同时验证了门禁本身：它既不假阳性，也不当橡皮图章。

### 6.7 实机在环验证（09:00，决定性）

设备已刷 PixelOS 并接入 adb（KernelSU `su`）。四条关键实测：

| 项 | 结果 |
|---|---|
| PixelOS 是否真启动 | ✅ `sys.boot_completed=1`，`ro.custom.version = PixelOS_pandora-17.0-20261102-0424`（正是本次分析的包） |
| 内核 | `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`，与 LOS **逐字相同** |
| 镜像 = 运行态？ | ✅ 抽样 40 个 `.ko` + 5 个索引文件，**全部 md5 相同** |
| 设备上的 fstab | sha256 `6a6f28e52f57…`，与 LOS **逐字节相同** |
| 已加载模块 | 666 个；`vendor_boot` 清单 169 唯一里只有 99 实际加载，`vendor_dlkm` 402 唯一里 311 |

**`0x797f2b3e` 至此由「按 stock 推断」升为「已实机启动验证」**；方案 B/C（源码重建）彻底出局。

**失败取证方案（下次刷 LOS 时用）**：`panic_on_oops=1` 且 ramoops 通道实测可用（`/sys/fs/pstore/pmsg-ramoops-0` 有内容）→ 若 LOS panic，**刷回 PixelOS 后读 `/sys/fs/pstore/console-ramoops-0`** 即可拿到 panic 栈，`ramoops` 是预留内存、跨重启保留。纯 userspace hang 留不下（`hung_task_panic=0`）。完整流程见交叉验证报告 §9.7。

> ⚠️ **LOS 的 OTA 包已从项目根目录删除**。全部 LOS 证据现只存在于 WSL `/root/work/gstack/`。重刷 LOS 前需重新构建或找回该包。

---

## ✅ 行动清单

| # | 行动 | 负责方 | 紧急度 | 验收判据 |
|---|---|---|---|---|
| 1 | **修复模块层：整目录替换（不是手工删条目）**：`$(KERNEL_PATH)/vendor_ramdisk/lib/modules/`、`vendor_dlkm/lib/modules/`、`system_dlkm_flatten/` 三处整体替换为 6.12.69 世代的同一份产物（stock 与 PixelOS 的这三处**逐字节相同**，任取其一）；`system_dlkm/` 版本化目录**不要动**。见 §6.5 | 移植 | P0 | 全量 `.ko` CRC 均为 `0x797f2b3e`；三处与 PixelOS 对应目录**逐字节相同**；`modules.load` 无悬空（8 条幽灵随整目录替换自然消失） |
| 2 | **构建期门禁**：接入 `scripts/maintain/kmi-gate.sh`，打包前校验「全量 `.ko` 的 `module_layout` CRC == `0x797f2b3e`」+「`modules.load` 每条都能在镜像内找到」+「vermagic 前缀 == 内核 banner」，任一不符即拒绝出包。**注意 C3（重复条目）只能 WARN**：原厂 stock 与 PixelOS 自己就有 263 条重复且能正常开机 | 移植 | P0 | 门禁在 LOS 现状报 FAIL（405/366/102 + 8/8/1 悬空）、在 stock 与 PixelOS 上报 PASS，已实测 |
| 3 | **取消 E1a / E1b / X2-mtime 门禁**：根因已不在 /data 侧 | QA | P1 | 矩阵 v4 中三者标记「取消」并注明理由 |
| 4 | **重写报告 §4.3 与结论**：删除「未 wipe 接管加密 /data」时间线，补「`-w` 只擦 metadata」；把 §2 模块层结论从「排除」改为「发现缺陷」 | 文档 | P1 | 结论章不再出现 version binding 作为主候选 |
| 5 | **修复后验证**：按第 1 条整目录替换后做正向 2/2 + 反向复现 2/2。**反向复现 = 只把三处模块层换回 LOS 原样**（清单、索引、`.ko` 一起回退），其余不动；判据为 `sys.boot_completed=1` 且启动期无 `disagrees about version of symbol module_layout`。失败时按 §6.7 的 pstore 流程取证（刷回 PixelOS 读 `console-ramoops-0`），不要凭日志猜 | QA | P2 | 反向复现故障必须重现；正向两次都能拿到 `boot_completed=1` |
| 6 | **E1c 后移至模块修复之后**：`fastboot erase userdata`（由 LOS 自己的 fs_mgr 走 `formattable` 重建）仍是唯一能回答「干净 /data 能否启动」的实验，但在模块世代修好之前做它没有意义 | QA | P2（条件） | 仅当模块修复后仍失败时才立项；须书面签收数据不可恢复 |
| 7 | ~~**执行边界落地（§5）**~~ **已完成**：新增 `wsl-common.sh` + `wsl-stage-init.sh`，`wsl-crc.sh` / `wsl-modinfo.sh` / `wsl-cover-vb.sh` / `wsl-fstab4.sh` 改为自包含并带存在性断言；`_work` 从 911 MB 降到 约 1.5 MB，中间态全部迁到 `/root/work/gstack`（实测跨 `wsl --terminate` 持久） | 移植 | ✅ | 清空 stage 后单跑任一脚本可自动初始化并给出与串联一致的结论 |
| 8 | **`.gitignore` 加白名单**：`*.ko` 之后补 `!device-trees/*/*/recovery/root/vendor/lib/modules/**/*.ko`，把两个 `exfat.ko` 纳入版本库 | 移植 | P1 | `git ls-files "*.ko"` 返回 2 条；新 clone 后 recovery 模块存在 |

**顺序纪律（不可让渡）**：先修模块世代（离线，零成本）→ 刷入验证 → 只有仍失败时才动 /data。
矩阵 v4 的原始排序把「取日志」放在最前，那是建立在「模块层已排除」的前提上；该前提已被 §2 推翻。

---

## ⚠️ 待完善 / 已知局限

- **「干净 /data 能否启动」这个假设至今未被验证**，只是被 §2 的模块缺陷盖住了。`-w` 从未格式化 userdata（§3.3），§27 的「清 data」是实验未执行（S0），§31 的 `-w` 也没碰 userdata。修好模块之后若仍失败，这条假设会重新浮上来——这正是 E1c 存在的理由。
- **取证对象是未刷入的产物**：本次解包的是 18:26 那次构建。缺陷在产物上是**证实**的，但对历史四次失败的因果归属依赖 §2.6 的推断，历史 `vendor_boot` 未留存、无法回溯。
- 「模块缺失导致探测期 panic」是机制推断，缺 `dmesg` 直接证据。修复后若能抓到 `disagrees about version of symbol module_layout`，即从推断升为证实。
- §27（卡动画）与 §33（卡第一屏）在本报告中被判为**另外两个独立故障**，本次未解决。
- `system_dlkm` 的 `flatten` 副本与版本化副本哪一份是运行期实际生效路径，本次未做代码级确认；两者都已给出各自的 CRC 分布，修复时建议都换。
- **`qa-fix-runbook.md` §7 有一处表述已由督导订正**：原写「WSL 空闲会重启、`/root` 不保留」，实测 `/root` 跨 `wsl --terminate` 持久、只有 `/tmp` 被清（见 §5.7 第 1 条），已改为正确表述。该订正只动了一行，不影响手册的步骤与判据。
- `modules.load` 的重复条目（LOS `vendor_dlkm` 195 条、stock / PixelOS 263 条）成因未查；两侧出货构建都有，判为固有形态而非缺陷。
- ~~**【11-02】PixelOS 能否在 pandora 上真正启动未验证**~~ → **已由 §6.7 证实**（`sys.boot_completed=1`，`ro.custom.version` 正是本次分析的包）。此条关闭。
- **【11-02】`init_boot.img` 只比了整文件哈希与 ramdisk 大小，未做逐文件比对**。两侧 sha256 不同（`23f9294a…` vs `c55cb7b8…`），ramdisk 段 **2,564,599 vs 2,841,989 字节（LOS 大 277 KB）**，但解包格式未探明（gzip 与 lz4-legacy 两种 magic 均未命中），差值来源未查。**「init 与 system 版本错配」这条候选仍未排除**——注意两侧 init 不同本身不是缺陷证据，两个 ROM 的 init 必然不同。
- **【11-02】`dtbo.img` 已取哈希，但未做语义比对**。整文件 sha256 `53094a7e…` vs `5688f25a…`（同为 33,554,432 字节），`vendor_boot` 内 `dtb` 段同为 6,557,139 字节但内容不同。**这同样不构成缺陷证据**——dtbo/dtb 携带 ROM 自己的板级覆盖，不同发行版必然不同。待做的只有一件：BoardConfig 声称 `BOARD_PREBUILT_DTBOIMAGE` 取自 stock，该声称尚未与 stock 的 `dtbo` 分区比对验证。
- **【11-02】PixelOS 的构建来源未知**（是否官方 CI）。本次只把它当「一个内部自洽的第三方参照」，不当权威基线。
- ~~**§5 的执行边界脚本尚未改造**~~ → **已完成**：新增 `wsl-common.sh`（持久 `STAGE=/root/work/gstack` + `need()` 存在性断言）与 `wsl-stage-init.sh`，5 个复核脚本改为自包含；`_work` 从 911 MB 降到约 1.5 MB，中间态全部迁到 WSL。此条关闭（行动清单第 7 条）。
- **动态验证只做到「PixelOS 能起」这一步，LOS 侧仍无在环证据**。11-02 09:00 设备已刷 PixelOS 并接入 adb（§6.7），但 LOS 修复后能否启动仍是**未验证**——这正是行动清单第 5 条要做的。修复前的全部结论基于镜像、日志、设备树与源码的交叉核对。

**方法说明**：本次在 WSL Ubuntu 24.04 下用 `debugfs`、`mount -t erofs`、`modinfo`、`modprobe --dump-modversions`、`fsck.erofs` 等真实工具复核了全部关键数值，与手写 Python 解析器的结果逐项一致。脚本在 `deliverables/gstack/_work/wsl-*.sh`，可一键复跑。

---

## 📚 成员产出索引

| 成员 | 产出 |
|---|---|
| 调查员 | `deliverables/gstack/_member/investigator-offline-evidence.md`（fstab 多来源比对、KMI 复核、CONFIG_PSTORE_RAM、fastboot-info 遍历） |
| QA 与发布 | `_member/qa-fix-runbook.md`（**修复执行手册**：方案选型 A1/A2/B/C、S0–S8 步骤、回滚、验收 8 条判据、三级反向复现）、`_member/qa-matrix-v4.md`（实验矩阵 v4；其 §9 结论成稿于 KMI 定案前） |
| 工程督导 | 本文 §2、§3、§5、**§6**（镜像解包、CRC 取数、BoardConfig 溯源、归属分层、执行边界与脚本整改、修复覆盖率验证、PixelOS 交叉验证） |
| 交叉验证 | `deliverables/gstack/pixelos-cross-reference-2026-11-02.md`（PixelOS 作为第三个独立基准：字节关系表、缺陷范围圈定、A1→A2 翻转、门禁对第三方的判定） |
| 中间产物 | `deliverables/gstack/_work/`（脚本与文本证据，约 1.5 MB；中间态在 WSL `/root/work/gstack/`） |
| 门禁 | `scripts/maintain/kmi-gate.sh`（C1 CRC / C2 悬空 / C3 重复，带 `-K` 内核 banner 校验；LOS 三集合 FAIL、stock 三集合 PASS，已实测） |
| WSL 复核脚本 | `wsl-common.sh`（公共前置与断言）、`wsl-stage-init.sh`（一键建 stage）、`wsl-fstab4.sh`（四来源 fstab）、`wsl-modinfo.sh`（vermagic）、`wsl-crc.sh`（CRC + PASS/FAIL）、`wsl-cover-vb.sh` / `wsl-cover.sh`（替换覆盖率）、`wsl-gate-kernel.sh`（banner 校验实测）、`wsl_extract_part.py`（payload 分区提取） |

**复跑方式**（WSL Ubuntu 24.04，需 root）：

```bash
wsl -d Ubuntu-24.04 -u root -- bash "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work/wsl-cover-vb.sh"
```

**一手证据**：`UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images/{boot,vendor_boot,vendor_dlkm,system_dlkm,vendor}.img`；`pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-*.zip` 的 `payload.bin`；`docs/fastboot-getvar-all.txt`；`docs/flash-log-1458/1609/v32-1809.txt`；`device-trees/los24-pandora/BoardConfig.mk`；`device-trees/pandora-dt/original/base-parts/*.dtb`。

---

> 本报告由软件工坊 AI 协作生成，关键决策请由工程负责人复核。
