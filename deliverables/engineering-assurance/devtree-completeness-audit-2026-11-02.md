# 小米 17 Pro（pandora / canoe / SM8850）设备树完整性审计

**审计范围**：`device-trees/los24-pandora/`（仓库内，24 文件）＋ WSL `/root/los24/device/xiaomi/{pandora,sm8850-common,pandora-kernel}` ＋ `vendor/xiaomi/sm8850-common`
**审计方式**：只读静态审计（未改任何文件，未执行构建）
**日期**：本次审计会话

---

## 1. 结论先行

| 口径 | 结论 | 依据 |
|---|---|---|
| **(a) 能编出 OTA 包（D1–D3）** | **是，闭合可用** | 继承链四段全部命中且外部依赖 14/14 存在；D1/D2/D3 已实测通过（`docs/los24-build-notes.md` §十三、`README.md` §LineageOS 24.0 完整 ROM 进度）。**但有前提**：依赖 `scripts/maintain/fix_ipa_headers.py` 等树外补丁，裸树 clone 下来编不过（见 §3 阻塞发布第 6 条） |
| **(b) 能进系统正常启动（D4）** | **未证实** | 没有任何一条证据能证明"当前这棵树的配置本身"能启动。D4 曾失败，根因是模块 KMI 世代错配（6.12.23 模块进 6.12.69 内核），修复动作是把 `pandora-kernel` 里模块目录整替换（`scripts/maintain/replace_kernel_modules.sh`），**属于二进制修复，不是设备树配置修复**。同时机型 blobs 至今不存在（`vendor/xiaomi/pandora` 未创建），意味着已启动验证过的那个包不含任何机型专属 blob —— "启动过"这件事**不能归功于这棵树** |
| **(c) 能作为独立仓库对外发布** | **不能** | 4 类资产缺失：通用树未入仓、内核未入仓、机型 blobs 与提取脚本从未生成、两棵树都没有 `lineage.dependencies`；且 Apache-2.0 合规不合格（无 LICENSE/NOTICE、零上游署名、provenance 已丢失） |

一句话：**"能编包"是真的；"配置完整"不成立 —— 接口层完整，资产层空洞。**

---

## 2. 完整性矩阵

状态口径：`有` = 定义存在且指向实际存在的文件；`缺` = 不存在；`可疑` = 存在但有悬空/无余量/静默跳过/语义不明。

### 2.1 继承链与合法性（问题 1）

| 类别 | 项 | 状态 | 证据（文件:行） | 影响 |
|---|---|---|---|---|
| 继承 | `lineage_pandora.mk` → `device.mk` | 有 | `lineage_pandora.mk:15` | — |
| 继承 | `lineage_pandora.mk` 基础三件套（core_64_bit_only / full_base_telephony / common_full_phone） | 有 | `lineage_pandora.mk:8,9,12`（顺序与 popsicle 一致） | — |
| 继承 | `device.mk` → `sm8850-common/common.mk` | 有 | `device.mk:8` | — |
| 继承 | `BoardConfig.mk` → `sm8850-common/BoardConfigCommon.mk` | 有 | `BoardConfig.mk:11`，用的是硬 `include`（非 `-include`），缺树即报错，方向正确 | — |
| 继承 | `common.mk` → `vendor/xiaomi/sm8850-common/sm8850-common-vendor.mk` | 有 | `common.mk:26`，硬 `inherit-product`（非 if-exists），缺 blob 树即失败 | — |
| 继承 | `BoardConfigCommon.mk` → `vendor/.../BoardConfigVendor.mk` | 有（内容为空壳，仅注释） | `BoardConfigCommon.mk:218`；`BoardConfigVendor.mk` 全 4 行均为注释 | extract-files 生成的空文件，正常 |
| **继承** | **机型 blobs 用 `-include` / `inherit-product-if-exists` 静默跳过** | **可疑** | `BoardConfig.mk:48`、`device.mk:13` | 这是本次 D1–D3 能"通"的直接原因，也是**最大隐忧**：包编出来了，但里面一条 pandora 专属 blob 都没有，构建期不会有任何告警 |
| 产品定义 | `AndroidProducts.mk` 指向 `lineage_pandora.mk` | 有 | `AndroidProducts.mk:7-8` | — |
| 产品定义 | lunch 目标名 ↔ 产物名 | 对得上 | `PRODUCT_NAME := lineage_pandora`（`lineage_pandora.mk:19`）；实测目标 `lineage_pandora-trunk_staging-userdebug`（`docs/los24-build-notes.md` §十三）；产物 `releases/Fastboot_lineage_pandora-20261102-1426.zip` | — |
| 产品定义 | 机型标识 | 有，且与设备实测一致 | `PRODUCT_MODEL := 25098PN5AC`（`lineage_pandora.mk:21`），`docs/los24-build-notes.md:179` 记录 `ro.product.model : 25098PN5AC` | — |
| 产品定义 | `BUILD_FINGERPRINT` | **可疑** | `lineage_pandora.mk:25` 写成 `Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM`，而同文件 `:24` 的注释与 `docs/los24-build-notes.md:181` 记录的原厂指纹是 `:16/BP2A.250605.031.A3/OS3.0.318.0.WBLCNXM`。**代号 `CP2A.260605.016` 在文档里找不到来源**，属人工构造 | 指纹与 vendor/build.prop（原厂 SPL）不一致会影响 Play Integrity / 部分银行与流媒体 App；对外发布时会被当"伪造指纹"质疑 |
| 产品定义 | `lineage.dependencies` | **缺** | 两棵树均无（`ls` 两处均 No such file） | LineageOS 构建体系靠它拉内核与公共树；没有它 = 第三方无法"clone 三仓即可编" |
| 一致性 | 仓库副本 ↔ 构建树 | **完全一致** | `diff -rq "device-trees/los24-pandora" /root/los24/device/xiaomi/pandora` 输出为空 | 仓库里这份就是真在编的那份，没有版本漂移 |

### 2.2 关键路径（问题 2，逐项"有/缺/可疑"）

| 类别 | 项 | 状态 | 证据 | 影响 |
|---|---|---|---|---|
| 内核 | `TARGET_KERNEL_SOURCE` | **可疑（悬空）** | `BoardConfig.mk:30` → `device/xiaomi/pandora-kernel/kernel-headers`，`ls -d` 实测 **No such file** | `generated_kernel_header_defaults` 走 `make -C $(TARGET_KERNEL_SOURCE) headers_install`，导出目录为空 → `linux/msm_ipa.h` 找不到。已在 `docs/los24-build-notes.md` §二十记录，用 `scripts/maintain/fix_ipa_headers.py` 改 `hardware/qcom-caf/sm8850/dataipa` 绕过。**这是树外补丁，新 clone 复现不了** |
| 内核 | `TARGET_KERNEL_VERSION` / `TARGET_KERNEL_PLATFORM_TARGET` | 未定义（`BoardConfigCommon.mk:104-108` 在 `ifeq ($(TARGET_OPT_IN_OSS_KERNEL),true)` 内） | 预编译路线下不需要，自洽 | — |
| 内核 | `TARGET_NO_KERNEL_OVERRIDE` | 有 | `BoardConfig.mk:29` | — |
| 内核 | 预编译 kernel 复制 | 有 | `BoardConfig.mk:32-33`；`pandora-kernel/kernel` 41,511,424 B 存在 | — |
| 内核 | `BOARD_PREBUILT_DTBOIMAGE` | 有（但被 `wildcard` 门控） | `BoardConfig.mk:26`，位于 `ifneq ($(wildcard $(KERNEL_PATH)/kernel),)`（`:25`）内 | 内核仓库一旦缺失，dtbo/dtb 配置会**静默变空**而不是报错——发布前必须确认只有一处真值 |
| 内核 | `BOARD_PREBUILT_DTBIMAGE_DIR` | 有 | `BoardConfig.mk:27`；`pandora-kernel/dtb/` 实含 12 个 `.dtb` | — |
| 内核 | 模块装载清单 | 有，且自洽 | `BoardConfig.mk:36-38` 读 `vendor_ramdisk/modules.load`(172)、`vendor_dlkm/modules.load`(665)、`modules.load.recovery`(466)；**全量比对：665 + 172 条每一条都能在对应目录（或 `system_dlkm/`）找到对应 `.ko`，悬空 0 条** | — |
| 内核 | `BOARD_VENDOR_KERNEL_MODULES`（模块**文件**清单） | **未定义** | 全树 grep 无 | 模块不是走 AOSP 安装路径，而是 `BoardConfig.mk:40-44` 用 `find-copy-subdir-files` 手搬。绕过 AOSP 的"清单↔文件"校验，漏一个 `.ko` 不会报错 |
| 内核 | `BOARD_VENDOR_KERNEL_MODULES_BLOCKLIST_FILE` | 未定义（预编译路线下） | `BoardConfigCommon.mk:112,114` 均在 OSS-kernel 分支内 | vendor_dlkm 无 `modules.blocklist`，与 stock 行为不同；对启动影响未核实 |
| fstab | 位置 | device/公共侧 | `sm8850-common/rootdir/etc/fstab.qcom`（71 行），`rootdir/Android.bp:6-11` 装成 `/vendor/etc/fstab.qcom` 且 `vendor_ramdisk_available` | 不在 vendor blob 侧，符合 LineageOS 惯例 |
| fstab | `TARGET_RECOVERY_FSTAB` | 有 | `BoardConfigCommon.mk:151` | — |
| fstab | 首阶段 fstab | 有 | `common.mk:338-339` 复制到 `vendor_ramdisk/first_stage_ramdisk/fstab.qcom` | — |
| fstab | 内容完整性 | 有 | 含 `metadata`/`avb=vbmeta`/`slotselect`/`logical`/`first_stage_mount`/`checkpoint=fs`/`quota`（`:38-71`） | — |
| recovery | 尺寸 | 有，与 stock 一致 | `BoardConfigCommon.mk:125` = 104,857,600；`docs/device-partitions.csv` recovery_a = 104,857,600 | — |
| recovery | `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE` | 有，且语义自洽 | `BoardConfigCommon.mk:149`；AOSP `build/make/core/board_config.mk:114,1069` 存在该变量与"未编 recovery 镜像时禁止设置"的硬约束，D3 通过说明约束满足 | recovery 镜像 kernel-less，依赖 boot 侧内核；**实机 recovery 能否独立启动未核实** |
| recovery | `BOARD_USES_RECOVERY_AS_BOOT` / `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT` | 未定义 | 全树 grep 无 | 与"独立 recovery 分区"路线自洽，不视为缺口 |
| vbmeta | AVB | 有 | `BoardConfigCommon.mk:169-187`：`BOARD_AVB_ENABLE`、boot/recovery/vbmeta_system 三套 key/alg/rollback、`--flags 3`、`BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT` | 全部用 `external/avb/test/data/testkey_rsa4096.pem`（AOSP 测试 key）→ **只能自签自用，不能与 stock 互刷**，发布时必须写进 README |
| super | 分区尺寸 | 有，与 stock **完全相等** | `BoardConfigCommon.mk:129` = 13,421,772,800；`docs/device-partitions.csv` super = 13,421,772,800 | — |
| super | 组尺寸 | 有，自洽 | `:131` = 13,417,578,496 = 13,421,772,800 − 4 MiB | — |
| super | 分组内容 | **可疑（设计选择）** | `:132` = `system system_dlkm system_ext product vendor vendor_dlkm odm`；而 stock super 组内还有 `mi_ext`（111,198,208 B，`docs/super-partitions.csv`） | 本构建不管理 mi_ext（`AB_OTA_PARTITIONS` 也无），mi_ext 保持原厂；`mi_ext/.../SoterService.apk` 走 `proprietary-files.txt` 重映射进 product（第 1733 行）→ 逻辑成立，但"重映射是否真的生效"未核实 |
| 尺寸 | boot / init_boot / vendor_boot / pvmfw | 全部有且与 stock 相等 | `:122,124,126,127` ↔ `docs/device-partitions.csv` boot 100,663,296 / init_boot 8,388,608 / vendor_boot 100,663,296 / pvmfw 1,048,576 | — |
| 尺寸 | `BOARD_DTBOIMG_PARTITION_SIZE` | **可疑（零余量）** | `:123` = 23,068,672（= stock `dtbo.img` 的**文件**大小），而 stock `dtbo` **分区**为 33,554,432 | 把镜像尺寸当分区上限写死，`dtbo` 若重新生成超过 22 MiB 就直接构建失败。当前 `device-trees/pandora-dt/build/dtbo.img` 仅 1,276,864 B，暂无实际风险 |
| A/B | `AB_OTA_UPDATER` / 分区清单 | 有 | `:13-30`，15 个分区（含 recovery、pvmfw、system_dlkm） | — |
| VAB | 虚 A/B | 有 | `:139` `BOARD_USES_METADATA_PARTITION`；`common.mk:8` `virtual_ab_ota/vabc_features.mk`；`common.mk:53` `PRODUCT_VIRTUAL_AB_COMPRESSION_METHOD := lz4` | — |
| 外部依赖 | mk 引用的 14 个跨仓路径 | **全部存在** | 逐一 `[ -e ]`：`device/qcom/sepolicy_vndr/SEPolicy.mk`、`hardware/qcom-caf/common/{common.mk,vendor_framework_compatibility_matrix.xml,compatibility_matrix_aidl.xml}`、`packages/modules/Virtualization/apex/product_packages.mk`、`hardware/qcom-caf/sm8850/audio/primary-hal/configs/canoe`、`vendor/qcom/opensource/power/config/canoe/powerhint.xml`、`hardware/nxp/{keymint,weaver}/generic`、`vendor/xiaomi/sm8850-common/{BoardConfigVendor,sm8850-common-vendor}.mk`、`vendor/qcom/opensource/vibrator/excluded-input-devices.xml`、`hardware/xiaomi`、`vendor/qcom/opensource/usb/etc` | — |
| 外部依赖 | `common.mk:286` 引用的 `NcmTetheringOverlay` | 有（不在本树） | `vendor/lineage/overlay/rro_packages/NcmTetheringOverlay` | 需 `vendor/lineage`，发布下游必须同步声明 |

### 2.3 通用配置（`sm8850-common`，184 文件 / 725,220 B）覆盖度（问题 3）

| 类别 | 项 | 状态 | 证据 | 备注 |
|---|---|---|---|---|
| configs/ | properties | 有（5 份，510 行） | `odm.prop` 123 / `vendor.prop` 295 / `system.prop` 41 / `product.prop` 29 / `system_ext.prop` 22 | 无其它机型名硬编码（grep `popsicle\|pudding\|myron\|athens\|songyuan\|pandora` 命中 0）→ 通用性 OK |
| configs/ | audio / perf / profiles / config.fs / modules | 有 | `audio/{audio_policy_configuration,audio_module_config_primary}.xml`、`perf/{perf,qape}configstore.xml`、`profiles/task_profiles.json`、`config.fs`、`modules/{modules.load,modules.load.recovery,modules.load.vendor_boot,modules.blocklist}` | — |
| configs/ | **modules.\* 三份在预编译路线下全部未生效** | 可疑 | `BoardConfigCommon.mk:111-116` 整体在 `ifeq ($(TARGET_OPT_IN_OSS_KERNEL),true)` 内 → 实际生效的是 `pandora-kernel` 里的 modules.load | 树里有 4 份 modules 清单，但真正被用的不是它 → 维护时极易改错文件 |
| rootdir/ | 7 个文件 + 安装规则 | 有 | `fstab.qcom`、`charger_fstab.qcom`、`init.qcom.rc`、`init.target.rc`、`init.xiaomi.rc`、`init.recovery.qcom.rc`、`ueventd.qcom.rc`；`rootdir/Android.bp` 7 个 `prebuilt_etc` 全部声明齐（含 `filename: "ueventd.rc"` 改名） | — |
| sepolicy/ | vendor 侧 | 有，覆盖面宽 | `sepolicy/vendor/` 62 个文件（约 48 个 `.te` + `file_contexts`/`genfs_contexts`/`property_contexts`/`service_contexts`/`vndservice_contexts`/`attributes`） | 静态只能证明"有"，**不能证明"够"**（见下） |
| sepolicy/ | public / private | 有 | public 1 个（`hal_touchfeature_xiaomi.te`）；private 3 个（`esimswitcher_app.te`、`parts_app.te`、`seapp_contexts`）+ `compat/` 8 个版本（30–34、202404、202504、202604） | LOS 24 compat 清单是 31–34 + 202404 + 202504，本树多带 202604 与 30.0，属冗余无害 |
| sepolicy/ | **域/genfs/file_contexts 覆盖是否够** | **未核实** | `docs/los24-static-analysis-report.md` §3.3 自己把"域缺失 / genfs 标签缺失 / file_contexts 未覆盖 / 属性未声明"列为**高度可疑**，且明确写"以上为预测，本项目尚未执行这些验证" | 本次审计亦无法离线判定，需 D4 日志（`avc: denied`） |
| vintf | `compatibility_matrix.*.xml` | 有 | `compatibility_matrix.device.xml` 3 个 `<hal>`；`compatibility_matrix.xiaomi.xml` 26 个 `<hal>` | — |
| vintf | **device manifest 侧几乎是空壳** | **可疑** | `configs/vintf/manifest_canoe.xml` 仅 2 行、**0 个 HAL**（`<manifest version="9.0" ...></manifest>`）；`manifest_xiaomi.xml` 6 行、**仅 1 个 HAL**（`vendor.qti.sla.service`） | 实际 HAL 声明依赖 blob 自带片段：`vendor/etc/vintf/manifest/` **100 个** + `odm/etc/vintf/manifest/` **6 个**。能跑，但"本设备声明了什么"在树里读不出来，reviewer 与后续维护者会误判为缺 HAL |
| overlays/ | common 8 个 / 机型 5 个 | 有 | common：`CarrierConfig/FrameworkRes/SecureElement/Settings/SystemUI/TelephonyRes/Wifi` + mk 引用的 `NcmTetheringOverlay`（在 `vendor/lineage`）；机型：`Aperture/FrameworksRes/Settings/SystemUI/Uwb` | `FrameworksResPandora` 内容有厚度：`config.xml` 507 行、`power_profile.xml` 177 行、`dimens.xml` 30 行、`irq_device_map.xml` |
| parts/ | `XiaomiParts` | 有 | `parts/Android.bp:7` 模块名 `XiaomiParts` ↔ `common.mk:342-343`；5 个 Kotlin 源 + `settings_touch.xml` + `strings.xml` | — |
| power/ | `libpowermode-ext-xiaomi` | 有 | `power/Android.bp:1` ↔ `common.mk:315` `soong_config_set qtipower` | — |
| alsd/ | `alsd` | 有 | `alsd/Android.bp:6` ↔ `common.mk:347` | — |
| aidl/interfaces | hypsys / micharge / citsensors / touchfeature | 有 | 4 组 AIDL（含 `aidl_api/*/current` 与 `.hash`）+ `aidl/` 下 2 个 service 实现 + `.rc`/`.xml` | `interfaces/citsensors/Android.bp.orig` 是遗留备份文件，建议发布前删 |
| 其它 | qcril-database / udfps | 有 | `qcril-database/config/0016.1_config.sql` + `Android.bp`；`udfps/UdfpsHandler.cpp` ↔ `common.mk:175 libudfpshandler` | — |

### 2.4 `proprietary-files.txt` ↔ 实际 blobs（问题 4）

**全量比对（不是抽样）**，映射规则 `proprietary/<entry>`，已剔除 `;FLAGS`、`|sha1`、`a:b` 重映射语法：

| 指标 | 数值 |
|---|---|
| `proprietary-files.txt` 总行数 / 有效条目 | 1978 / **1758** |
| `vendor/xiaomi/sm8850-common` 实际文件数 / 体积 | 1741 / **669,394,080 B（638 MiB）** |
| **清单条目在实体中找不到** | **211 条 = 12.0%** |
| 缺失分布 | `vendor/` 118、`odm/` 89、`system_ext/` 2、`system/` 1、`mi_ext/` 1 |
| 缺失形态 | 父目录存在但单个文件缺 **108** 条；整目录缺 **10** 条（`canoe_{cdp,mtp,qrd}_slc` 的 acdb 变体等） |
| 缺失内容聚类 | ① `vendor/etc/acdbdata/` 的 slc SKU 变体与语音模型（`.pmd`/`.eai`）；② Qualcomm AI 栈（`libQnn*`、`libtensorflowlite_c_qcom`）；③ AVF/qcvm 虚拟化件（`avf_qcvm_manager`、`qtvm`）；④ `soundfx` 空间音频库 |

判读：**这不是"清单写错了"，而是"blobs 不是从 pandora 的完整 dump 抽出来的"**。上游 `proprietary-files.txt` 覆盖 5 台 8850 机型（README 明列 pudding/popsicle/myron/athens/songyuan，**没有 pandora**），所以一部分条目本来就不属于本机；但 108 条"父目录在、文件不在"说明抽取过程本身有遗漏。**已构建的 OTA 就是在缺这 211 条的情况下编出来的**——这也解释了为什么 `vendor/xiaomi/pandora` 至今为空、机型专属 blob 一条都没有。

---

## 3. 缺口清单（按影响分档）

### A. 阻塞发布（不补完不能对外发）

1. **通用树未入仓** —— `sm8850-common`（184 文件 / 725,220 B）只在 WSL 构建树里，仓库 `device-trees/` 下无对应目录。补：新建仓库或子目录。
2. **内核仓库未入仓** —— `pandora-kernel` 279 MiB（kernel 41.5 MB、dtbo 23.0 MB、`vendor_dlkm` 402 个 `.ko`、`vendor_ramdisk` 461 个 `.ko`、`system_dlkm` + `system_dlkm_flatten` 103 个 `.ko`），仓库内完全没有。补：Release 资产或 git-lfs（见 §4）。
3. **机型 blobs 与提取链从未生成** —— `vendor/xiaomi/pandora` 不存在；机型树里也没有 `proprietary-files.txt` / `extract-files.py` / `setup-makefiles.py`（对比 popsicle：1813 行清单 + 45 行 firmware 清单 + 两个脚本齐全）。补：以 popsicle 为模板，从 pandora 的 OTA/设备 dump 生成。
4. **`lineage.dependencies` 缺失（两棵树都没有）** —— 第三方无法"三仓齐 clone 即编"。
5. **许可证不合规** —— 详见 §4.3。
6. **构建不自洽：依赖树外补丁** —— `fix_ipa_headers.py`（改 `hardware/qcom-caf/sm8850/dataipa`）、`fix_blob_deps.py`、`fix_wfd_elfcheck.py`、`fix_qcwcn_common.py`、`fix_rildb_filegroups.py`、`fix_sepolicy_compat.py` 等 6+ 个 `scripts/maintain/*.py` 是构建的必要条件，而它们不在设备树里。**下游 clone 三仓后 `m bacon` 会失败**。补：把这些改动沉进 `sm8850-common`（多数本来就是该树的配置），或提供 `patches/` 目录 + README 步骤。
7. **零文档** —— 两棵树都没有 README（连机型支持列表、维护者、所需 SPL/固件版本、刷机前置条件都没有）。

### B. 阻塞启动（未核实，需实机证据）

1. **机型 blobs 缺失** —— 现在这个 OTA 不含 pandora 专属 vendor 内容。启动验证的结论不能归因于"配置正确"，只能归因于"sm8850-common 的 blobs 恰好够用"。**这是本次审计最想让人正视的一条。**
2. **`configs/keylayout/Xiaomi_Touch_Input_1.idc` 缺失** —— popsicle 有（`device.mk:28-29` 复制到 `/vendor/usr/idc/`），pandora 的 `configs/` 下只有 `properties/` 一层；且 blobs 里 `find -name "*.idc" -o -name "*.kl"` **命中 0** → 这份 idc 在整条链上无处可来。影响触控校准/UDFPS 唤醒行为，是否致命未核实。
3. **sepolicy / genfs / file_contexts 覆盖** —— 见 §2.3，`docs/los24-static-analysis-report.md` §3.3 自己列为"高度可疑但尚未验证"。
4. **内核↔模块世代** —— 本次核到：`pandora-kernel/kernel` 的版本串与 VERMAGIC 为 `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`，`system_dlkm_flatten`（与内核同批出的 GKI 模块）vermagic 同串；而 `vendor_dlkm` 402 个 + `vendor_ramdisk` 461 个 `.ko` 全部是短式 `6.12.69-android16-6-4k`。**vermagic 字符串差异本身是无害的**（`CONFIG_MODVERSIONS=y` 时 `same_magic()` 跳过 vermagic，判据是 `module_layout` CRC —— 这点在 `deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md:141` 已有相同结论）。但**替换后模块的 CRC 是否等于内核期望的 `0x797f2b3e`，本次未复核**（该项目自己的风险表第 7 条也仍标 🟠：`system_dlkm` 目录名已换、`vendor_ramdisk`/`vendor_dlkm` 未换）。

### C. 只是不完整（不影响出包，影响可维护性/可复现性）

1. `BOARD_VENDOR_KERNEL_MODULES` 未定义 → 模块靠 `find-copy-subdir-files` 手搬，缺失不报错。
2. `BOARD_VENDOR_KERNEL_MODULES_BLOCKLIST_FILE` 未定义 → vendor_dlkm 无 blocklist。
3. `configs/modules/modules.{load,load.recovery,load.vendor_boot,blocklist}` 四份在预编译路线下**未生效**，树里留着会被改错。
4. `BOARD_DTBOIMG_PARTITION_SIZE` 取镜像尺寸而非分区尺寸（22 MiB vs 32 MiB），零余量。
5. `manifest_canoe.xml` 空壳 + `manifest_xiaomi.xml` 仅 1 个 HAL，真实声明全在 blobs 的 106 个 fragment 里。
6. `mi_ext` 未进 `BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST`，`SoterService.apk` 走重映射进 product（是否真生效未核实）。
7. `persist.vendor.fingerprint.type` 在 `sm8850-common/configs/properties/{odm,vendor}.prop` 与 `pandora/configs/properties/odm.prop` 三处重复（值都是 `udfps`，无行为冲突，但属冗余）。
8. `interfaces/citsensors/Android.bp.orig` 遗留备份文件。
9. `pandora` 树无 `configs/keylayout`、无 `sepolicy/`、无 `recovery/root`、无 `Android.mk`（soong-only 够用，但意味着机型级任何 SELinux/触控差异都无处安放）。
10. 上游 README 的机型支持列表**不含 pandora**（列的是 Pudding/Popsicle/Myron/Athens/Songyuan）→ 对外发布时必须自己声明"pandora 为移植机"。

---

## 4. 发布方案

### 4.1 仓库结构：建议 3 仓（机型 / 公共 / 内核）

| # | 仓库 | 内容 | 体积（apparent） |
|---|---|---|---|
| 1 | `android_device_xiaomi_pandora` | 现有 24 文件 + `lineage.dependencies` + `README.md` + `LICENSE` | **42,759 B（42 KB）** |
| 2 | `android_device_xiaomi_sm8850-common` | 184 文件（含 overlays 资源、parts Kotlin、sepolicy、AIDL） | **725,220 B（708 KB）** |
| 3 | `android_device_xiaomi_pandora-kernel` | kernel / dtbo.img / dtb / vendor_ramdisk / vendor_dlkm / system_dlkm(_flatten) | **292,527,356 B（279 MiB）** |

**为什么拆、不合并："** `sm8850-common` 是 8850 家族的公共物（上游自述支持 5 台机），和 pandora 的生命周期不同：上游更新公共树时，你只需要 `git merge upstream`；合成单仓就得手工 diff 184 个文件。内核更必须独立——279 MiB 二进制和 42 KB 的 mk 文件放一起，任何人的 clone 体验都会崩。

**反例（什么情况下应该合成单仓双子目录）**：如果只维护 pandora 一台、永远不做上游同步、也不打算让第三方复用，那么单仓 `device/xiaomi/{pandora,sm8850-common}` 更省事——少一次 commit 协调、`lineage.dependencies` 也不用维护。**判断依据是：你打算不打算跟上游 lolipuru 继续同步。** 打算同步 → 3 仓；只此一台、不再跟踪上游 → 单仓。

### 4.2 包含 / 排除清单

**进 git**：所有 `*.mk` / `*.bp` / `*.xml` / `*.prop` / `*.te` / `*.rc` / `*.aidl` / `*.kt` / `*.cpp` / `*.py`(提取脚本) / `README.md` / `LICENSE` / `NOTICE` / `lineage.dependencies`。

**不进 git**：
- `vendor/xiaomi/sm8850-common/proprietary/`（638 MiB，1741 文件）—— LineageOS 通行做法：只入库 `proprietary-files.txt` + `extract-files.py` + `setup-makefiles.py`，用户自己从 OTA/设备提取。
- `pandora-kernel` 的二进制（279 MiB）—— 走 Release 资产（`pandora-kernel-<date>.tar.zst`，模块可压到 ~40%）。
- 现有的 `*.img`、`pandora-ota_*.zip`、`PixelOS_*/`、`sysonly/` —— 现行 `.gitignore` 已覆盖。

**注意一个坑**：现行根 `.gitignore` 里有 `*.img`、`*.ko`、`*.dtb`、`*.zip`，而 `pandora-kernel` 的内容**恰好全在这几类里**（`kernel` 本身无扩展名，会被提交；`dtbo.img`/`*.ko`/`*.dtb` 全被忽略）。如果要在当前仓库里放内核目录，必须给它单独的 `.gitignore` 或 `git add -f`，否则会得到"只有 kernel 没有模块"的半残提交。

### 4.3 许可证处理（当前最薄弱的一环）

现状（全部实测）：

| 事实 | 证据 |
|---|---|
| 根 `LICENSE` 是 MIT，且已写明 `device-trees/` 沿用上游 Apache-2.0 | `LICENSE` 全文 + `README.md:349-355` —— **方向正确** |
| 但 `device-trees/los24-pandora/` 下**没有 LICENSE 文件** | 24 文件清单里无 |
| `sm8850-common` 下**没有 LICENSE，也没有 NOTICE** | `ls -a` 只有 `README.md` 与源码目录 |
| 所有文件头写 `Copyright (C) 2026 The LineageOS Project` + `SPDX-License-Identifier: Apache-2.0` | 例：`BoardConfig.mk:1-4`、`common.mk:1-5`、`Android.bp:1-4` |
| **零上游署名** | `grep -ril "lolipuru" sm8850-common` → **0 命中** |
| **provenance 已丢失** | `sm8850-common/.git` 是**断链符号链接**（`cat` 报 No such file），指不到任何对象库；`popsicle`、`pandora-kernel` 均非 git 仓库 |

Apache-2.0 的实际义务（§4）：随分发提供许可证副本；保留原有版权/NOTICE；**对修改过的文件显著声明已修改**；不得暗示原作者为你背书。当前状态三条都不满足，把上游代码的版权头直接改成 "The LineageOS Project" 更是**反向操作**——这既不是 LineageOS 的代码，也不是你的原创。

**补法（可执行清单）**：
1. `device-trees/los24-pandora/LICENSE` ← Apache-2.0 全文；`NOTICE` 写：`This device tree is derived from <上游仓库URL> (author: lolipuru), Apache-2.0. Modifications: pandora 机型适配、A17 化、odm.prop/overlays 重写。`
2. 同法给 `sm8850-common` 补 `LICENSE` + `NOTICE`；**文件头保留上游版权行**，把本项目贡献写成 `Copyright (C) 2026 <你的名字>` 追加一行，并加 `# Modified for pandora (LineageOS 24)` 注释。
3. 上游 URL 与 commit 需要**重新获取**（`.git` 已断链，无法从本地推出）—— 这是唯一一项必须联网取证的。
4. `pandora-kernel` 属小米分发物：**建议不入 git、只在 Release 以"从 OS4.0.5.0.XBLCNXM 提取"形式分发，并在 README 声明版权归小米、仅用于个人研究**。这与现行 `README.md:355` 的口径一致。

### 4.4 体积估算

| 方案 | 仓库 git 体积 | 说明 |
|---|---|---|
| 机型树 | ~60 KB | 42 KB + git 开销 |
| 公共树 | ~900 KB | 708 KB + git 开销 |
| 内核（Release 资产，不入 git） | 0 | 发布资产 `tar.zst` 估 110–130 MB（279 MiB，`.ko` 可压到 ~40%） |
| 内核（若强行入 git） | ~280 MB+，且每次改二进制都要重写历史 | **不推荐** |
| blobs（不入 git） | 0 | 638 MiB，用户自提 |
| **合计（推荐方案）** | **< 1 MB 的 git，~120 MB Release** | 无单文件超 GitHub 100 MB 硬限（实测最大单文件：blob `libQnnHtpPrepare.so` 51.8 MB、内核 `kernel` 41.5 MB、`dtbo.img` 23.0 MB、`qca_cld3_peach_v2.ko` 21.4 MB；**全资产 >100 MB 的文件数 = 0**）|
| 反例：连 blobs 一起推 | **~915 MB** | 接近 GitHub 1 GB 建议上限，且每次 OTA 更新都会重写 638 MiB 历史 |

### 4.5 `git` / `gh` 步骤草案（**不执行，仅供评审**）

```bash
# ── 0. 准备一个干净的落地目录（不污染当前仓库）
mkdir -p ~/pub/pandora/{device,pandora-kernel}
cp -a "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/device-trees/los24-pandora/." ~/pub/pandora/device/
cp -a /root/los24/device/xiaomi/sm8850-common/. ~/pub/pandora/sm8850-common/
cp -a /root/los24/device/xiaomi/pandora-kernel/. ~/pub/pandora/pandora-kernel/

# ── 1. 补证件（见 §4.3）
#   ~/pub/pandora/device/{LICENSE,NOTICE,README.md,lineage.dependencies}
#   lineage.dependencies 内容形如：
#     [{"remote":"github","repository":"<org>/android_device_xiaomi_sm8850-common","target_path":"device/xiaomi/sm8850-common"},
#      {"remote":"github","repository":"<org>/android_device_xiaomi_pandora-kernel","target_path":"device/xiaomi/pandora-kernel"}]

# ── 2. 机型树仓
cd ~/pub/pandora/device
git init -b lineage-24.0
git add -A && git commit -m "pandora: initial device tree for Xiaomi 17 Pro (canoe/SM8850)"
gh repo create <org>/android_device_xiaomi_pandora --public \
   --description "LineageOS 24 device tree for Xiaomi 17 Pro (pandora)" --source=. --push

# ── 3. 公共树仓
cd ~/pub/pandora/sm8850-common
git init -b lineage-24.0
git add -A && git commit -m "sm8850-common: import from upstream <URL>@<commit>, add NOTICE"
gh repo create <org>/android_device_xiaomi_sm8850-common --public --source=. --push

# ── 4. 内核：只存"提取脚本 + 校验清单"，二进制走 Release
cd ~/pub/pandora/pandora-kernel
printf '*.ko\n*.img\n*.dtb\nkernel\nsystem_dlkm/\nvendor_dlkm/\nvendor_ramdisk/\n' > .gitignore
# 入库内容：extract 脚本、modules.load 三份、sha256 清单、README（含来源机型/固件版本）
git init -b lineage-24.0 && git add -A && git commit -m "pandora-kernel: loader manifest + extraction scripts"
tar -I 'zstd -19 -T0' -cf ../pandora-kernel-OS4.0.5.0.tar.zst .
gh release create v1.0-OS4.0.5.0 ../pandora-kernel-OS4.0.5.0.tar.zst \
   --title "pandora-kernel (from OS4.0.5.0.XBLCNXM)" --notes "Extracted from Xiaomi stock OTA. Copyright Xiaomi."

# ── 5.（可选）机型 blobs 仓：只放清单 + 提取脚本，不放 blob 实体
#   git init → 只提交 proprietary-files.txt / extract-files.py / setup-makefiles.py
```

---

## 5. 需要用户拍板的问题（3 条）

1. **发布形态选哪种？** 3 仓（机型 / 公共 / 内核，可持续跟上游同步）还是 1 仓双子目录（只维护 pandora、不再跟上游）？判断依据就一条：**以后还同不同步 lolipuru 的 `sm8850-common`**。
2. **279 MiB 内核二进制放哪？** Release 资产（推荐，git 里 <1 MB）／ 独立仓库 + git-lfs（每次更新体积翻倍）／ 直接进 git（不推荐，历史会膨胀到 280 MB+）。另外 kernel 与 dtbo 属小米分发物，**要不要在 README 明确"仅个人研究、版权归小米"**？
3. **先补 blobs 再发布，还是先发"实验性"版本？** 现状是机型 blobs 从没生成过、清单里有 211 条（12%）对不上、idc 缺失。若先发布，必须在 README 顶部标注"**未经完整启动验证、缺机型专属 blob**"，否则第三方按 README 刷机会踩你踩过的坑。

---

## 附：本次审计的"未核实"清单（不要当成"应该没问题"）

- sepolicy 域 / genfs / file_contexts 是否覆盖 A17 新 HAL —— 需 D4 的 `avc: denied` 日志
- 替换后模块的 `module_layout` CRC 是否等于 `0x797f2b3e` —— 需跑 `scripts/maintain/kmi-gate.sh`
- `SoterService.apk` 的 `mi_ext → product` 重映射是否真的生效 —— 需解包产物
- recovery 镜像（kernel-less）能否独立启动 —— 需实机
- 211 条缺失 blob 中，哪些是 pandora 真正需要、哪些只是其它 8850 机型的 —— 需 pandora 完整 dump 后重跑比对
- 上游 lolipuru 的具体 URL 与 commit —— `.git` 已断链，需联网取证
