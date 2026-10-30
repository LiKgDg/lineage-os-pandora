#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from sm8850-common
$(call inherit-product, device/xiaomi/sm8850-common/common.mk)

# Get non-open-source specific aspects
# 机型专属 blobs 由 tools/ 从 stock OTA 提取生成；
# 尚未生成时不阻塞配置阶段。
$(call inherit-product-if-exists, vendor/xiaomi/pandora/pandora-vendor.mk)

# Camera
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator-V1-ndk.vendor \
    vendor.qti.hardware.camera.offlinecamera-V2-ndk.vendor

# Overlays
# 初始值继承自 popsicle（同为 1220x2656 / 520dpi），
# 刷机后需按 stock overlay 逐项核对，见 docs/los24-build-notes.md
PRODUCT_PACKAGES += \
    ApertureOverlayPandora \
    FrameworksResPandora \
    SettingsOverlayPandora \
    SystemUIResPandora \
    UwbResPandora

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# UWB
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.uwb.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.uwb.xml
