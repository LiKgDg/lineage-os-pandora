# 第一阶段 B：system-only 移植执行报告

设备：Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）
源码：LineageOS 23.2（Android 16）
日期：2026-10-30

---

## 一、路线选择

完整 ROM 需要 `hardware/qcom-caf/sm8850`，而 LineageOS 23.2 最高只到 `sm8750`，
因此改走 **system-only 移植**：

| 分区 | 来源 |
|---|---|
| `system` / `system_ext` / `product` | LineageOS 23.2 编译产物 |
| `vendor` / `odm` / `vendor_dlkm` / `system_dlkm` | stock 保持不动 |
| `boot` / `init_boot` / `vendor_boot` / `dtbo` / `vbmeta` | stock 保持不动 |

可行性依据：stock vendor 本身就是 Android 16（`system-sdk 36`），
与 LOS 23.2 的 VNDK 同代，不依赖 sm8850 CAF 源码。

---

## 二、已落地配置

### 新增产品变体

`device/xiaomi/pandora/lineage_pandora_sysonly.mk`，并在 `AndroidProducts.mk` 注册：

```
lineage_pandora_sysonly-bp4a-userdebug
lineage_pandora_sysonly-bp4a-user
```

### BoardConfig 分支

```make
ifeq ($(TARGET_PRODUCT),lineage_pandora_sysonly)
TARGET_NO_KERNEL := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
TARGET_NO_RECOVERY := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE :=
endif
```

### VINTF 放宽

stock vendor 的 device compatibility matrix 要求 framework 提供：

- `android.frameworks.sensorservice`
- `vendor.qti.hardware.sigma_miracast_aidl`
- `vendor.qti.qccsyshal_aidl`（`IQccsyshal/default`）

后两者是小米/QTI 的框架侧扩展，LOS 不构建。因此：

- `PRODUCT_ENFORCE_VINTF_MANIFEST := false`
- 用自建的最小设备矩阵 `device/xiaomi/pandora/vintf/compatibility_matrix.xml`
  （只声明 `<system-sdk><version>36</version></system-sdk>`）

### 刷机通道

`device.mk` 增加 `PRODUCT_PACKAGES += fastbootd`。
逻辑分区只能由 fastbootd 写入；fastbootd 用 liblp 直接改写**现有** super 的元数据，
不需要在 PC 上重建 `super.img`，也就不用猜 `metadata-slots` / group 布局。
触发条件已确认：`bootable/recovery/etc/init.rc` 的
`on property:sys.usb.config=fastboot → start fastbootd`。

---

## 三、编译过程中解决的环境问题

| 问题 | 现象 | 解决 |
|---|---|---|
| lunch 目标名 | `Invalid lunch combo: lineage_pandora-userdebug` | 必须用 `lineage_pandora-bp4a-userdebug`（见 `COMMON_LUNCH_CHOICES`） |
| `TARGET_COPY_OUT_VENDOR_DLKM` | `board_config.mk:816` 报必须设置 `BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE` | 不要置空这些类型变量 |
| recovery 冲突 | `board_config.mk:1060` 禁止 `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE` | sysonly 分支里把它置空 |
| blob 包抢占路径 | `hardware/nxp/keymint` 与 blob 的 `prebuilt_etc` 抢 `vendor/etc/permissions/*.xml` | sysonly 不需要 blob，临时 `mv Android.bp Android.bp.hold` |
| `python` 缺失 | genrule 报 `python: command not found`（Ubuntu 24.04 只有 `python3`） | `ln -sf /usr/bin/python3 /usr/local/bin/python` |
| `java` 缺失 | `extract-r8-rules: exec: java: not found` | 构建脚本显式 `export JAVA_HOME` + 干净 PATH |
| PATH 污染 | WSL PATH 含 `Program Files (x86)`，`(` 导致命令解析失败 | 构建脚本用干净 PATH，不追加 `$PATH` |
| OOM | `-j24` 下 23 GiB 打满，`Out of memory: Killed process ninja` | 降到 `-j12`，加 8 GiB swapfile，`vm.swappiness=10` |
| swap 抖动 | swap 用掉 26 GiB，构建几乎不推进 | `wsl --shutdown` 重启清 swap 与页缓存 |

磁盘不是瓶颈：实测写 4.3 GB/s、读 1.4 GB/s。

---

## 四、当前编译进度

- soong 模块图完整生成：`out/combined-lineage_pandora_sysonly.ninja`
- 初始 133,429 个任务，已编译过半（日志推进到 SystemUI 的 dex 阶段）
- `system.img` / `system_ext.img` / `product.img` **尚未产出**

---

## 五、剩余阻塞：框架层 aconfig 重复类

```
Type com.android.wifi.flags.Flags is defined by both the program:
  .../SystemUI/android_common/withres/SystemUI.jar:com/android/wifi/flags/Flags.class
and the library:
  .../wifi_framework_aconfig_flags_lib/.../wifi_framework_aconfig_flags_lib.jar:com/android/wifi/flags/Flags.class
```

**性质**：`frameworks/base/packages/SystemUI/Android.bp` 里并没有直接引用
`wifi_framework_aconfig_flags_lib`（已 grep 确认），冲突来自传递依赖——
`framework-wifi` 静态带入 flags 库的同时，该库又被作为独立 aconfig 库链接。

这是 **源码树内部版本不一致**（`frameworks/base` 与 `packages/modules/Wifi`
的 aconfig flag 导出方式不同代），与设备树无关。

**标准解法**：`repo sync -d` 让全树回到 manifest 指定版本，
或单独把 `packages/modules/Wifi` 同步到与 `frameworks/base` 匹配的 revision。

---

## 六、下一步

1. **同步源码树**：`repo sync -d -j16`（重点 `frameworks/base`、`packages/modules/Wifi`），
   然后重跑 `m systemimage systemextimage productimage`。
2. **产出镜像后**：
   - `m recoveryimage`（含 fastbootd），`fastboot flash recovery_a recovery.img`
   - `adb reboot fastboot` 进入 fastbootd
   - `fastboot flash system system.img` / `system_ext` / `product`
   - `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`
3. **首次开机排查**：`adb logcat` + `/sys/fs/pstore`，重点看
   `vintf` 兼容性告警、`init` 的 `Failed to start` 服务、`dm-verity`。

---

## 七、构建脚本

`staging/build_sysonly.sh`：限时（500 s）续跑 + 日志追加到 `/root/sysonly_build.log`。
ninja 是增量的，反复调用即可累积进度，适合受会话时长限制的环境。

注意：直接调用 `out/combined-lineage_pandora_sysonly.ninja` 可跳过 kati 重分析，
但必须自己 `export JAVA_HOME` 并使用干净 PATH，否则 genrule 找不到 `java`/`python`。
