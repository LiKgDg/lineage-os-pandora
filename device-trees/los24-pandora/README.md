# Device tree — Xiaomi 17 Pro (`pandora` / `canoe` / SM8850)

LineageOS 24.0 (Android 17) device tree for the Xiaomi 17 Pro, codename **pandora**,
Qualcomm platform **canoe** (SM8850).

> **实验性移植，未经验证可启动。** 请先读完「当前状态」与「已知缺口」两节再决定要不要刷。
> This is an experimental port. Read 「当前状态」 and 「已知缺口」 before flashing anything.

---

## 当前状态

| 口径 | 状态 | 说明 |
|---|---|---|
| 能编出 OTA 包 | ✅ 已验证 | `lunch lineage_pandora-trunk_staging-userdebug` → `m nothing`（30:07，0 error）→ `mka bacon`（1.19 GB OTA）。上述构建发生在**已应用树外补丁**的源码树上：至少包括 `fix_ipa_headers`（`docs/los24-build-notes.md` §二十）与 `fix_blob_deps`（§十一）；其余四个补丁是否都在该次构建中应用过，**未逐条核实** |
| 能刷入并正常启动 | ❌ **未验证** | 最近一次刷入启动**未通过**（停在开机动画）。根因已定位为内核模块 KMI 世代错配（873 个 `.ko` 按 6.12.23 编译却装入 6.12.69 内核，`module_layout` CRC 不符）。修复方式是把 `pandora-kernel` 内的模块目录整目录替换（**二进制级替换，不是配置修改**）；替换后**是否可启动未验证** |
| 可作为独立仓库发布 | ⚠️ 实验性 | 本仓已补齐 LICENSE / NOTICE / `lineage.dependencies`。但机型专属 blobs 尚未生成（见下），照本仓说明构建出的包**不含任何 pandora 专属 vendor 内容** |

**一句话：能编包是真的；"配置完整、能开机"没有证据支撑。**

---

## 已知缺口（发布时刻的真实状态，不要当成 TODO 清单美化版）

### 1. 机型专属 blobs 不存在（最严重）

`vendor/xiaomi/pandora` **从未生成**。本树的 `device.mk` 用的是
`inherit-product-if-exists`、`BoardConfig.mk` 用的是 `-include`，缺树时**静默跳过**：

```make
# device.mk
$(call inherit-product-if-exists, vendor/xiaomi/pandora/pandora-vendor.mk)
# BoardConfig.mk
-include vendor/xiaomi/pandora/BoardConfigVendor.mk
```

后果：构建不会报错，但产物里没有一条 pandora 专属 blob。**这也是"能编包"能通过的直接原因**。
补齐方式见下节「自行提取 blobs」。

### 2. 通用树 `proprietary-files.txt` 与实际 blobs 对不上 12%

`sm8850-common` 的 `proprietary-files.txt` 有 1758 条有效条目，其中 **211 条（12.0%）**
在 `vendor/xiaomi/sm8850-common/proprietary/` 中找不到对应实体（vendor 118 / odm 89 /
system_ext 2 / system 1 / mi_ext 1）。其中 108 条是"父目录存在但文件缺失"，10 条是整目录缺失。
缺失内容集中在 acdbdata 的 SKU 变体与语音模型、Qualcomm AI 栈（`libQnn*`）、AVF/qcvm 虚拟化件。

已构建的 OTA 就是在缺这 211 条的情况下编出来的。

### 3. 触控 idc 缺失

`configs/keylayout/Xiaomi_Touch_Input_1.idc` **不存在**（上游 popsicle 树有这一份，
本树的 `configs/` 下只有 `properties/` 一层）。且 blobs 中 `find -name "*.idc" -o -name "*.kl"`
命中 0 —— 这份 idc 在当前链路上无处可来。影响触控校准与可能的 UDFPS 唤醒行为，**是否致命未核实**。

### 4. 裸 clone 无法直接 `m bacon`：需要 6 个树外补丁

下列脚本改的是**设备树以外的源码**，不在任何发布仓里。每个脚本都对应一类已记录的真实构建失败
（脚本文档头有完整背景），但它们是否为某次成功构建的**全部**必需项，**未逐条核实**：

| 脚本 | 解决什么 |
|---|---|
| `fix_ipa_headers.py` | 预编译内核没有 `kernel-headers/`（`TARGET_KERNEL_SOURCE` 指向不存在的目录），`qti_ipa_kernel_headers` 导出为空 → `libipanat` / `ipacm` 报 `linux/msm_ipa.h` not found。改用 dataipa 自带的 UAPI 头（`drivers/platform/msm/include/uapi`） |
| `fix_blob_deps.py` | `libwfdcommonutils` 的 `shared_libs` 是从 `.so` 的 `DT_NEEDED` 全量导出的，含 `libdng_sdk` → 触发 `xmp_toolkit_sdk` / `zuid_md5` 整条 vendor 变体级联失败 |
| `fix_wfd_elfcheck.py` | 上一条摘掉依赖后，`check_elf_file` 报 `DT_NEEDED "libdng_sdk.so" is not specified in shared_libs` |
| `fix_qcwcn_common.py` | `driver_cmd_nl80211_common.h` 在头文件里写了不带 `extern` 的全局定义 → `lib_driver_cmd_qcwcn` 的 `drv` / `bss` 重复符号 |
| `fix_rildb_filegroups.py` | qcril 配置数据库 genrule 依赖的 `proprietary_rildb_config_sql_files` / `proprietary_rildb_other_sql_files` filegroup 在 A17 blob 包里缺定义 |
| `fix_sepolicy_compat.py` | `treble_sepolicy_tests_202604` 报「新增 public type 未登记到 compat mapping」→ 补 `private/compat/<ver>/<ver>.ignore.cil` |

这些脚本在 `lineage-os-pandora` 主仓的 `scripts/maintain/` 下。**没有它们，三仓齐全也编不过。**

### 5. 指纹是人工构造的

`lineage_pandora.mk` 里的 `BUILD_FINGERPRINT` 写成
`Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM:user/release-keys`，
而实测原厂指纹是 `Xiaomi/pandora/pandora:16/BP2A.250605.031.A3/OS3.0.318.0.WBLCNXM:user/release-keys`。
代号 `CP2A.260605.016` 没有任何来源记录。**与 vendor 侧 SPL 不一致会影响 Play Integrity 及部分银行/流媒体 App。未核实其实际影响范围。**

### 6. AVB 使用 AOSP 测试 key

`sm8850-common/BoardConfigCommon.mk` 的 boot / recovery / vbmeta_system 三套 key 全部指向
`external/avb/test/data/testkey_rsa4096.pem`。**只能自签自用，不能与 stock 互刷**；回锁需自备 key。

### 7. 其它

- `BOARD_DTBOIMG_PARTITION_SIZE := 23068672`（22 MiB）取的是 stock `dtbo.img` **文件大小**，
  而 stock `dtbo` **分区**是 32 MiB（33554432）→ dtbo 重新生成超 22 MiB 会直接构建失败，零余量。
- `BOARD_VENDOR_KERNEL_MODULES` 未定义，模块靠 `find-copy-subdir-files` 手搬，漏文件不报错。
- `configs/vintf/manifest_canoe.xml` 是 2 行空壳（0 个 HAL），真实声明来自 blobs 自带的
  100 个 `vendor/etc/vintf/manifest/*.xml` + 6 个 `odm/etc/vintf/manifest/*.xml`。

---

## 仓库与依赖

本仓是三个仓库中的**机型树**，另两个由 `lineage.dependencies` 声明：

| 仓库 | 内容 |
|---|---|
| `LiKgDg/android_device_xiaomi_pandora`（本仓） | 机型树（24 文件 + LICENSE/NOTICE/README/lineage.dependencies） |
| `LiKgDg/android_device_xiaomi_sm8850-common` | 8850 家族公共设备配置（上游 `lolipuru/android_device_xiaomi_sm8850-common` 的快照 + pandora 适配） |
| `LiKgDg/android_device_xiaomi_pandora-kernel` | **只含提取脚本与清单**，不含内核二进制（小米分发物，不随源码分发） |

```
device/xiaomi/pandora
├── Android.bp                      soong namespace
├── AndroidProducts.mk              -> lineage_pandora.mk
├── BoardConfig.mk                  机型板级配置（include sm8850-common/BoardConfigCommon.mk）
├── device.mk                       机型 package 列表（inherit sm8850-common/common.mk）
├── lineage_pandora.mk              产品定义
├── lineage.dependencies            另两个仓库
├── configs/properties/odm.prop     机型属性（取自 stock）
├── overlays/                       5 个 RRO：Aperture / FrameworkRes / Settings / SystemUI / UWB
├── LICENSE                         Apache-2.0 全文
├── NOTICE                          上游出处 + 修改声明
└── README.md                       本文件
```

---

## 构建前置

1. **LineageOS 24.0 源码树**（Android 17），`repo sync` 完整。
2. 三个仓库按下面的路径就位：

   ```
   device/xiaomi/pandora              <- 本仓
   device/xiaomi/sm8850-common        <- 公共树
   device/xiaomi/pandora-kernel       <- 内核（自行提取，见 kernel 仓 README）
   vendor/xiaomi/sm8850-common        <- 公共 blobs（自行提取）
   vendor/xiaomi/pandora              <- 机型 blobs（**目前不存在，需自行生成**）
   ```

3. **打上面「已知缺口 §4」列出的 6 个补丁**，否则 `m` 会在 `libipanat` / vendor 变体等处失败。
4. **不要使用 `TARGET_OPT_IN_OSS_KERNEL=true`** —— 上游只支持 pudding/myron 从源码编内核；
   pandora 走预编译内核路线。

```bash
source build/envsetup.sh
lunch lineage_pandora-trunk_staging-userdebug
mka bacon
```

---

## 自行提取 blobs（当前缺失，必须做）

```bash
# 1. 解原厂 OTA 全量包（增量包会被拒绝，退出码 2）
python3 tools/payload_dump.py pandora-ota_full-*.zip stock/ --verify

# 2. 生成机型 blob 清单与 soong 包
#    参数形式：<输出目录> <分区>=<挂载点> [...]
python3 tools/gen_blob_list.py vendor/xiaomi/pandora \
    vendor=/mnt/pv odm=/mnt/po system_ext=/mnt/pse
python3 tools/gen_vendor_bp.py vendor/xiaomi/pandora

# 3. 产出 proprietary-files.txt、proprietary/<part>/...、Android.bp、pandora-vendor.mk
```

工具在 `lineage-os-pandora` 主仓 `tools/` 下。提取完成后本树
`inherit-product-if-exists` / `-include` 才会真正生效。

内核（`boot` / `vendor_boot` / `vendor_dlkm` / `system_dlkm` / `dtbo`）的提取方式见
`android_device_xiaomi_pandora-kernel` 仓的 README。

---

## 未核实事项（不要当成"应该没问题"）

- 刷入后能否启动 —— 未验证
- sepolicy 域 / genfs 标签 / file_contexts 是否覆盖 A17 新增 HAL —— 需实机 `avc: denied` 日志
- 替换后模块的 `module_layout` CRC 是否等于 `0x797f2b3e` —— 需跑 `scripts/maintain/kmi-gate.sh`
- kernel-less recovery 镜像能否独立启动 —— 需实机
- `BUILD_FINGERPRINT` 与 vendor 侧不一致对 Play Integrity / 支付类 App 的影响范围
- 本仓与上游 `sm8850-common` HEAD 的逐条差异 —— **未逐条比对**

---

## 许可证

本仓代码采用 **Apache License 2.0**，全文见 `LICENSE`；上游出处、快照时间与修改声明见 `NOTICE`。
上游每个源文件自带的 `SPDX-License-Identifier: Apache-2.0` 与 `Copyright (C) 2026 The LineageOS Project`
文件头**均未修改**。

本仓不包含任何小米版权二进制。`Xiaomi` 为小米公司商标；本项目与小米公司、LineageOS 项目均无隶属关系。
