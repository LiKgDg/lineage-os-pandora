# LineageOS product config for Xiaomi 17 Pro (pandora / canoe)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)
$(call inherit-product, device/xiaomi/pandora/device.mk)

PRODUCT_DEVICE := pandora
PRODUCT_NAME := lineage_pandora
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 25098PN5AC
PRODUCT_MANUFACTURER := Xiaomi
