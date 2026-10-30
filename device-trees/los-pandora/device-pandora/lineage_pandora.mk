# LineageOS product config for Xiaomi 17 Pro (pandora / canoe / SM8850)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
$(call inherit-product, device/xiaomi/pandora/device.mk)

# 厂商 blob 包（由 tools/gen_vendor_mk.py 从官方 payload 生成）
$(call inherit-product-if-exists, vendor/xiaomi/pandora/pandora-vendor.mk)

PRODUCT_DEVICE := pandora
PRODUCT_NAME := lineage_pandora
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 25098PN5AC
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_SYSTEM_NAME := pandora
PRODUCT_SYSTEM_DEVICE := pandora

TARGET_SUPPORTS_64_BIT_APPS := true
