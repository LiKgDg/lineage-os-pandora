# 第一阶段：完整 LineageOS ROM 编译与设备适配 —— 执行报告

设备：Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）
源码：LineageOS 23.2（Android 16，`PLATFORM_VERSION=16`）
内核：`6.12.23-android16-5-g75e9b1c7ae7c`（预编译 `Image`，39,963,136 B，KMI `android16-5`）
日期：2026-10-29

---

## 一、阶段目标与交付物

| 编号 | 交付物 | 状态 |
|---|---|---|
| D1 | 编译环境校验记录 | ✅ 完成 |
| D2 | 源码树 + 设备树就位校验 | ✅ 完成 |
| D3 | 官方全量 OTA 分区镜像导出 | ✅ 完成（12 个分区 / 5.2 GB） |
| D4 | `vendor/xiaomi/pandora` blob 包 | ✅ 已生成（未编译验证） |
| D5 | 完整 ROM 设备树配置 | ✅ 已落地 |
| D6 | `m bacon` 产出可运行 ROM | ❌ **硬阻塞**，见第五节 |

---

## 二、环境校验（D1）

```
内核宿主      Linux 6.18.40.1-microsoft-standard-WSL2 / Ubuntu 24.04.5
CPU / 内存    16 核 / 23 GiB
磁盘          1007 GiB，可用 682 GiB（源码树 270 GiB）
ccache        命中 3098/9439 = 32.8%
JDK           由 prebuilts/jdk 提供（非系统 java）
lunch 目标    lineage_pandora-bp4a-userdebug
```

`lunch` 输出确认：

```
PLATFORM_VERSION=16
LINEAGE_VERSION=23.2-20261029-UNOFFICIAL-pandora
TARGET_PRODUCT=lineage_pandora
PRODUCT_SOONG_NAMESPACES=device/xiaomi/pandora vendor/xiaomi/pandora
```

> 注意：`lunch lineage_pandora-userdebug` 会报 `Invalid lunch combo`，
> 正确目标由 `AndroidProducts.mk` 的 `COMMON_LUNCH_CHOICES` 决定，必须是
> `lineage_pandora-bp4a-userdebug`。

---

## 三、分区镜像导出（D3）

官方包 `pandora-ota_full-OS3.0.318.0.WBLCNXM-user-16.0-*.zip`（8.78 GB）
是标准 A/B payload OTA（`ota-type=AB`，`pre-device=pandora`），
`payload.bin` 在 zip 内**未压缩存储**，可流式解析。

工具：`tools/payload_dump.py`（自研，支持 REPLACE / REPLACE_BZ / REPLACE_XZ / ZERO / DISCARD）

关键实现点：`InstallOperation.data_offset` 是**相对 payload 数据区**的偏移，
必须加上 `24 + manifest_size + metadata_signature_size`（本例 322223）才是文件绝对偏移。
这一点错了会直接 `LZMAError: Input format not supported by decoder`。

payload 共 **57 个分区**，主要分区实测尺寸：

| 分区 | 大小 (B) | 分区 | 大小 (B) |
|---|---|---|---|
| system | 912,457,728 | vendor | 902,373,376 |
| system_ext | 710,426,624 | odm | 3,547,955,200 |
| product | 4,520,914,944 | vendor_dlkm | 54,063,104 |
| mi_ext | 111,198,208 | system_dlkm | 16,912,384 |
| boot | 100,663,296 | init_boot | 8,388,608 |
| vendor_boot | 100,663,296 | dtbo | 23,068,672 |

导出结果（`/root/pandora-stock`，共 5.2 GB）：`boot` `init_boot` `vendor_boot`
`dtbo` `vbmeta` `vbmeta_system` `vendor` `odm` `vendor_dlkm` `system_dlkm`
`system_ext` `mi_ext`。

校验：`init_boot.img` 头部 `ANDROID!` 正确；`vendor/odm/system_ext/mi_ext/vendor_dlkm`
均为 **EROFS**，`mount -o loop,ro` 挂载成功。

---

## 四、厂商 blob 包（D4）

`vendor` + `odm` 挂载后统计：**3369 + 2456 = 5825 个文件**（848 M + 3.3 G）。

`tools/gen_blob_list.py` 产出：

```
entries=6135  files=5825  symlinks=310  bytes=6133107727 (5.71 GiB)

shared_lib   2291
etc          2187
firmware      964
executable    361
apk            19
apex            2
jar             1
symlink       310
```

`tools/gen_vendor_bp.py` 产出 soong 包：**5811 个模块**
（`Android.bp` 1.6 MB + `pandora-vendor.mk`）。

### 为什么用 soong 而不是 Android.mk

第一版用 make（`BUILD_PREBUILT`）生成 5824 个模块，`m nothing` 直接失败：

```
build/make/core/base_rules.mk:513: error: overriding commands for target
out/target/product/pandora/odm/etc/NOTICE.xml.gz,
previously defined at out/soong/installs-lineage_pandora.mk:288839
```

make 与 soong 各自为同一分区生成 `NOTICE.xml.gz`，目标冲突。
现代 LineageOS blob 包一律是 soong 的 `Android.bp`，改成
`cc_prebuilt_library_shared` / `cc_prebuilt_binary` / `prebuilt_etc` /
`android_app_import` 后该错误消失。

### 已修正的生成器缺陷

| 缺陷 | 现象 | 修法 |
|---|---|---|
| `prebuilt_etc` 的 `sub_dir` 未剥掉 `etc/` 前缀 | 装到 `/vendor/etc/etc/audio/...` | 剥离前缀 |
| `NOTICE*` 被当作 blob | 与 soong 的 NOTICE 目标冲突 | 提取阶段过滤 |
| `android_app_import` 用了 `stem` | `unrecognized property "stem"` | 该类型无 `stem`，改用模块名即文件名 |
| overlay APK 走了 app_import | 安装路径错误（应在 `/vendor/overlay`） | 暂时跳过，待 `runtime_resource_overlay` |

---

## 五、编译验证结果与硬阻塞（D6）

### 5.1 已越过的关卡

`m nothing`（完整模块图校验）第二轮已不再报 NOTICE 冲突，
说明产品配置、blob 命名空间、soong 解析都正常。

### 5.2 当前失败：73 个路径的打包冲突

```
error: module "lineage_pandora_generated_vendor_image":
packaging conflict at lib64/libutils.so
  blob_vendor_lib64_libutils_so   -> vendor/lib64/libutils.so
  libutils                        -> vendor/lib64/libutils.so
```

共 **274 条错误 / 73 个唯一路径**，例如
`libutils.so` `libhidlbase.so` `librilutils.so` `server_configurable_flags.so`
`android.system.suspend-V1-ndk.so` `vibrator.default.so` `bin/sh` `bin/toolbox`
`bin/dumpsys` `bin/logwrapper`。

**性质**：这类库 AOSP 会自己从源码编译，blob 不应重复打包。
标准解法是从 `proprietary-files.txt` 里剔除，或给 blob 模块加
`overrides: ["libutils"]` 让其覆盖源码模块。属于机械性长尾工作，
不影响可行性判断。

### 5.3 硬阻塞：LineageOS 源码树没有 sm8850 平台支持

```
hardware/qcom-caf/  →  bootctrl bt common msm8953 msm8998 sdm660 sdm845
                       sm8150 sm8250 sm8350 sm8450 sm8450-6.6 sm8550
                       sm8650 sm8750 thermal thermal-legacy-um wlan
```

**最高只到 `sm8750`（骁龙 8 Elite），没有 `sm8850`。**
全树搜索 `sm8850` 只有一处命中，就是我们自己写的
`device/xiaomi/pandora/BoardConfig.mk`。

完整 ROM 需要的高通 CAF HAL 全部缺失：

- `hardware/qcom-caf/sm8850/{display,audio,media,gps,bt,wlan}`
- `vendor/qcom/opensource/{display,audio-hal,dataservices,power,thermal-engine}`
  的 sm8850 目标分支
- 对应的 `device/qcom/sm8850-common` 平台公共配置

因此 **在当前 LineageOS 源码下无法编译出可运行的完整 ROM**。
这不是配置问题，是平台移植工作量问题：需要把整套 CAF HAL 栈移植到新 SoC，
属多人数月级工程，且需真机反复联调。

---

## 六、结论与后续路径

### 结论

1. 第一阶段的**数据与配置基础已完成**：分区镜像、blob 包、完整产品配置、
   可解析的 soong 模块图。
2. **"编译出可运行完整 ROM" 在当前源码条件下不可达**，根因是
   LineageOS 尚无 sm8850 平台支持，与设备树质量无关。
3. 已越过的两个真实错误（NOTICE 冲突、路径重复）都已修复，
   剩余的 73 个打包冲突是机械性清理。

### 可行路径（按性价比排序）

**路径 A：系统侧移植（推荐先做）**
保留 stock 的 `vendor` / `odm` / `vendor_dlkm` / `system_dlkm` / `boot` /
`init_boot` / `vendor_boot` / `dtbo` 完全不动，只把 `system` + `system_ext` +
`product` 换成 LineageOS 编译产物。因为 stock vendor 本身就是 Android 16，
与 LOS 23.2 的 VNDK 同代，兼容性最好。这条路不依赖 sm8850 CAF 源码。

**路径 B：等 / 移植 sm8850 CAF**
跟踪 `hardware/qcom-caf` 是否新增 sm8850 分支；或以 sm8750 为基础
patch 出 sm8850（需真机联调 display/audio/camera）。

**路径 C：清理 73 个打包冲突后先让 `m bacon` 跑通**
能产出 zip，但因缺 HAL 无法开机，价值仅在于验证构建管线。

### 立即下一步

1. 清理 73 个打包冲突（剔除或 `overrides`），让 `m bacon` 至少产出 zip。
2. 转向路径 A：把 `lineage_pandora.mk` 拆成 system-only 变体，
   `TARGET_NO_KERNEL` + 复用 stock 镜像，先争取开机。
3. 设备恢复可用后，用 `recovery-pandora-dualkey.img` 刷 `recovery_a` 验证。
