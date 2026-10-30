# Recovery 卡刷 OTA：签名校验与 SPL 降级拦截

Xiaomi 17 Pro（pandora / canoe / SM8850）LineageOS 23.2 recovery 适配案例。
本文记录「adb sideload 刷入小米官方全量 OTA 失败」的完整定位过程与修复。

---

## 一、现象

自编译的 LineageOS recovery（TWRP 风格设备树，`kernel_size=0`）里执行：

```
adb reboot sideload
adb sideload pandora-ota_full-OS3.0.318.0.WBLCNXM-user-16.0-082e9f32b8.zip
```

表现为：

1. 传输到中途（曾观察到 47%）长时间不动；
2. 或提示 **"Signature verification failed"**，点 "Yes" 强行安装后卡在该界面；
3. 最终 `Install completed with status 1` / `Installation aborted.`

---

## 二、先排除的三个错误方向

### 1. `/sideload` 不需要挂载任何分区

`bootable/recovery/install/fuse_sideload.cpp` 把 adb 推上来的数据流做成一个
**FUSE 虚拟文件系统**，路径固定为 `/sideload/package.zip`。该文件在磁盘上并不存在，
所以「挂到哪个分区才能刷」这个问法本身不成立。

### 2. `/data` 挂不上是设计如此

设备使用 metadata 加密（dm-default-key），recovery 没有 crypto 支持
（`TW_INCLUDE_CRYPTO := false`）。`/metadata` 可手动挂载，`/data` 挂不上不影响 sideload。

### 3. `setup_install_mounts()` 会主动卸载

`recovery_utils/roots.cpp:437` 只挂 `/tmp`、`/cache`，其余全部卸载。
这是正常流程，不是故障。

---

## 三、根因一：OTA 签名证书不匹配

### 证据

第一版 recovery 的 `/system/etc/security/otacerts.zip` 只有一把证书：

```
testkey.x509.pem    1675 B
```

而小米官方 OTA 包内 `META-INF/com/android/otacert` 是另一把：

```
subject = C=CN, ST=Beijing, L=Beijing, O=Xiaomi, OU=MIUI, CN=MIUI,
          emailAddress=miui@xiaomi.com
SHA256  = D4:5F:07:6F:E2:3A:1A:5B:7F:48:6E:3F:F4:15:47:A2:
          02:3D:BF:E1:FE:73:35:3B:1E:48:EB:DF:ED:72:CC:6F
```

recovery 的 `verifier.cpp` 只会用 otacerts.zip 里的公钥校验整包签名，
**只信任 testkey 时，任何小米官方包都必然校验失败**。

### 修复

`otacerts.zip` 由 soong 的 `otacerts_zip` 模块生成
（`build/soong/etc/otacerts_zip.go`），它会读取：

- `PRODUCT_DEFAULT_DEV_CERTIFICATE`（默认 testkey）
- `PRODUCT_EXTRA_RECOVERY_KEYS` / `PRODUCT_EXTRA_OTA_KEYS`（额外公钥，自动追加 `.x509.pem`）

因此把小米公钥放进设备树，并在 `device.mk` 里登记：

```
device/xiaomi/pandora/security/xiaomi.x509.pem
```

```make
PRODUCT_EXTRA_RECOVERY_KEYS += device/xiaomi/pandora/security/xiaomi
PRODUCT_EXTRA_OTA_KEYS      += device/xiaomi/pandora/security/xiaomi
```

重编后镜像内变成两把证书：

```
testkey.x509.pem    1675 B
xiaomi.x509.pem     1594 B
```

### 验证（真机日志）

```
I:2 key(s) loaded from /system/etc/security/otacerts.zip
Verifying update package...
I:failed to verify against RSA key 0
I:whole-file signature verified against RSA key 1
Update package verification took 279.3 s (result 0).
```

`result 0` = 校验通过，签名问题闭环。

---

## 四、根因二：SPL 降级被误判

### 证据

签名通过后立刻被拦：

```
W:Current SPL: 2026-10-01 Target SPL: 2026-07-01 this is considered a downgrade
ERROR: recovery: Denying OTA because it's SPL downgrade
```

### 为什么是误判

`bootable/recovery/install/install.cpp` 用的是：

```cpp
android::base::GetProperty("ro.build.version.security_patch", "")
```

在 recovery 环境里，这个属性取自**当前 recovery 镜像自己的 prop.default**，
也就是 LineageOS 23.2 的构建时间（SPL 2026-10-01），
**不是设备上真实 HyperOS 固件的 SPL**。

所以只要 LOS 构建比小米包新，刷任何小米包都会被判降级——纯属张冠李戴。

同一个逻辑还影响 `CheckAbSpecificMetadata()` 里的时间戳降级检查：
它比较 `ro.build.date.utc`（同样是 LOS 构建时间）与包的 `post-timestamp`。

### 修复

`install.cpp` 增加 `ro.recovery.allow_spl_downgrade` 开关，置 1 时：

- 直接 `spl_downgrade_approved = true`，跳过拒绝；
- 同时跳过 `ask_to_continue_spl_downgrade()` 交互确认
  （sideload 期间 UI 线程被占用，弹窗会死锁）。

`device.mk`：

```make
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += ro.recovery.allow_spl_downgrade=1
```

真机确认：

```
adb shell getprop ro.recovery.allow_spl_downgrade   →  1
```

---

## 五、其它已确认的适配点

| 项 | 结论 |
|---|---|
| boot HAL | LOS 23.2 只认 AIDL，HIDL 1.1 报 `no longer supported`；改用 `android.hardware.boot-service.default_recovery` |
| `early_hal` | `init.rc` 的 `on boot` 只 `class_start default/hal`，需在 `init.recovery.qcom.rc` 补 `class_start early_hal` |
| `update_engine_sideload` | AOSP 只在 cuttlefish 加，真机必须自己进 `PRODUCT_PACKAGES` |
| `kernel_size` | 必须为 0：本机 ABL 从 `boot_a` 取内核，带内核的 recovery 会退回 fastboot |
| 屏幕 | 1220×2656 / density 520 → `ro.recovery.ui.margin_width/height = 52` |
| lunch 目标 | `lineage_pandora-bp4a-userdebug`（不是 `lineage_pandora-userdebug`） |

---

## 六、刷机命令（A 槽，不动 B 槽）

```bash
fastboot flash recovery_a recovery-pandora-dualkey.img
fastboot reboot recovery
adb reboot sideload
adb sideload pandora-ota_full-OS3.0.318.0.WBLCNXM-user-16.0-082e9f32b8.zip
```

- `fastboot` 用 35.0.2（37.0.1 刷大文件会 `bad_alloc` / `Too many links`）
- `adb sideload` 报 `Total xfer: 1.00x` 表示传输完整；`Install completed with status 0` 才是安装成功
- 传输期间 host 侧百分比会长时间不动，那是 `tr`/CRT 缓冲，不是卡死

---

## 七、关于「编译完整 LineageOS ROM」的结论

当前设备树 `device/xiaomi/pandora/` 只有：

```
Android.bp  Android.mk  AndroidProducts.mk  BoardConfig.mk
bootctrl/   device.mk   gpt-utils/          kernel-headers/
lineage_pandora.mk      prebuilt/{Image,dtb,dtbo.img}
recovery/   system.prop  security/
```

**没有任何 `proprietary-files.txt` / vendor blob**，`vendor/xiaomi/` 为空。
这是一棵纯 recovery（TWRP 风格）设备树，`m recoveryimage` 能出包，
但 `m bacon` / 全量 ROM 缺少全部厂商 HAL（audio、camera、display、sensors、RIL…），
无法产出可开机的 super。

要真正跑起 LineageOS，还需要：从官方包提取 vendor blob → 写 `proprietary-files.txt`
→ 适配各 HAL 的 device 配置 → 修 SELinux 策略 → 处理 vendor_dlkm 与 GKI 模块匹配。
这是独立于本 recovery 工程的另一阶段工作。
