LOCAL_PATH := device/xiaomi/pandora

PRODUCT_USE_DYNAMIC_PARTITIONS := true
ENABLE_VIRTUAL_AB := true

# recovery 侧 bootctrl HAL。缺了它 update_engine 会报
# "Error getting bootctrl v1.0 module" 并中止 OTA。
PRODUCT_PACKAGES += \
    android.hardware.boot@1.1-impl-qti.recovery \
    bootctrl.canoe.recovery

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
