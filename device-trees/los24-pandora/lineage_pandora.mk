#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from pandora device.
$(call inherit-product, device/xiaomi/pandora/device.mk)

## Device identifier
PRODUCT_DEVICE := pandora
PRODUCT_NAME := lineage_pandora
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 25098PN5AC
PRODUCT_MANUFACTURER := xiaomi

# 取自 stock：Xiaomi/pandora/pandora:16/BP2A.250605.031.A3/OS3.0.318.0.WBLCNXM
BUILD_FINGERPRINT := Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM:user/release-keys

# GMS
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
