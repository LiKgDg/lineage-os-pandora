# recovery 里的 adb 需要免认证：LOS 的 vendor/lineage/config/common.mk 在非 eng
# 构建下会写 ro.adb.secure=1，必须在此处（inherit 之前）定义 WITH_ADB_INSECURE。
WITH_ADB_INSECURE := true

# LineageOS system-only 产品配置（第一阶段 · 路径 A）
#
# 目标：只产出 system / system_ext / product 三个镜像，
# 保留 stock 的 vendor / odm / vendor_dlkm / system_dlkm /
# boot / init_boot / vendor_boot / dtbo 完全不动。
#
# 之所以可行：stock vendor 本身就是 Android 16（SDK 36），
# 与 LineageOS 23.2 的 VNDK 同代，不需要 sm8850 CAF 源码。
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, device/xiaomi/pandora/device.mk)

PRODUCT_DEVICE := pandora
PRODUCT_NAME := lineage_pandora_sysonly
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 25098PN5AC
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_SYSTEM_NAME := pandora
PRODUCT_SYSTEM_DEVICE := pandora

TARGET_SUPPORTS_64_BIT_APPS := true

# 关键：system-only 不做 VINTF 强制校验。
# stock vendor 的 device compatibility matrix 要求 framework 提供
#   android.frameworks.sensorservice
#   vendor.qti.hardware.sigma_miracast_aidl
#   vendor.qti.qccsyshal_aidl (IQccsyshal/default)
# 后两者是小米/QTI 的框架侧扩展，LOS 不构建，强制校验必然失败。
PRODUCT_ENFORCE_VINTF_MANIFEST := false

# 不要把厂商 blob 打进 system（它们属于 vendor，stock 已有）
PRODUCT_PACKAGES += \
    DeviceAsWebcam

# 显式声明要构建 recovery：TARGET_NO_KERNEL=true 时 board_config.mk:503
# 会因此把 BUILDING_RECOVERY_IMAGE 置空，导致 BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE 报错。
PRODUCT_BUILD_RECOVERY_IMAGE := true
