LOCAL_PATH := device/xiaomi/pandora

PRODUCT_USE_DYNAMIC_PARTITIONS := true
ENABLE_VIRTUAL_AB := true

# recovery 侧 bootctrl HAL。缺了它 update_engine 会报
# "Error getting bootctrl v1.0 module" 并中止 OTA。
PRODUCT_PACKAGES += \
    android.hardware.boot@1.1-impl-qti.recovery \
    bootctrl.canoe.recovery

# LOS 23.2 的 update_engine 已经**不支持 HIDL 1.1**：
#   BootControlClient.cpp(414) IBootControl HIDL versions 1.1 and earlier are no longer supported
# 只认 AIDL 的 android.hardware.boot.IBootControl。
# 上面那两个 qti 包是 HIDL 1.1，只能作为备用；真正让 update_engine 找到 HAL 的是这个
# AOSP 官方 AIDL 实现（recovery: true，自带 init_rc，通过 misc 分区的 BCB 读写槽位）。
PRODUCT_PACKAGES += \
    android.hardware.boot-service.default_recovery

# adb sideload 的实际执行者。recovery 二进制里硬编码了
# /system/bin/update_engine_sideload（bootable/recovery/install/install.cpp:330），
# 但 AOSP 只在 cuttlefish 的 device.mk 里把它加入 PRODUCT_PACKAGES，
# 真机产品必须自己加，否则 recovery 里一按 Apply from ADB 就找不到可执行文件。
PRODUCT_PACKAGES += \
    update_engine_sideload

PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

PRODUCT_PROPERTY_OVERRIDES += \
    ro.adb.secure=0 \
    ro.boot.dynamic_partitions=true \
    vendor.gatekeeper.disable_spu=true \
    ro.dynamic.full_size=13421772800

# 屏幕 1220x2656 / density 520 → recovery UI 边距 52px
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.recovery.ui.margin_width=52 \
    ro.recovery.ui.margin_height=52

# 小米官方 HyperOS OTA 包（pandora-ota_full-*.zip）用的是小米自己的签名密钥
# （CN=MIUI, O=Xiaomi），与本 recovery 的 AOSP testkey 不同。
# 不注入这把公钥，recovery 校验时会直接报 "Signature verification failed"，
# 用户点 "Yes" 强行安装也会因为 update_engine 校验 payload 失败而中止。
# soong 的 otacerts_zip 模块会自动为每个条目追加 .x509.pem 后缀，
# 并把 testkey + 这里列出的密钥一起打进 /system/etc/security/otacerts.zip。
PRODUCT_EXTRA_RECOVERY_KEYS +=     device/xiaomi/pandora/security/xiaomi

PRODUCT_EXTRA_OTA_KEYS +=     device/xiaomi/pandora/security/xiaomi

# recovery 判定"SPL 降级"时用的 ro.build.version.security_patch / ro.build.date.utc
# 取自 LineageOS 自身的构建，与设备上真实固件无关。LOS 23.2 的 SPL 比 HyperOS
# 全量包新，因此刷任何小米官方包都会被误判为降级并直接中止（"Denying OTA because
# it's SPL downgrade"）。置 1 后 install.cpp 会强制放行。
PRODUCT_DEFAULT_PROPERTY_OVERRIDES +=     ro.recovery.allow_spl_downgrade=1

# ── 完整 ROM 追加配置（第一阶段新增） ────────────────────────────────
# 厂商 blob 只在完整 ROM（lineage_pandora）里继承；
# system-only 变体的 vendor 由 stock 提供，不能重复打包。
# 设备侧 overlay / 权限
PRODUCT_PACKAGES += \
    DeviceAsWebcam

# 允许未实现的 HAL 依赖（bring-up 阶段）
PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := false

# 关闭需要 sm8850 CAF 源码才能提供的特性（当前源码树最高只到 sm8750）
TARGET_USES_QCOM_MM_AUDIO := false

# fastbootd：system-only 移植的刷机通道。
# 逻辑分区（system/system_ext/product…）只能由 fastbootd 写入，bootloader 的
# fastboot 看不到它们。fastbootd 用 liblp 直接改写现有 super 的元数据，
# 不需要在 PC 上重建 super.img，也就不用猜 metadata-slots / group 布局。
PRODUCT_PACKAGES +=     fastbootd
