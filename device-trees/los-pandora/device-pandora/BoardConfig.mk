#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/pandora

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := false

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := generic

# Power
ENABLE_CPUSETS := true
ENABLE_SCHEDBOOST := true

# Bootloader
PRODUCT_PLATFORM := canoe
TARGET_BOOTLOADER_BOARD_NAME := canoe
TARGET_NO_BOOTLOADER := true
TARGET_USES_UEFI := true

# Platform
TARGET_BOARD_PLATFORM := canoe
QCOM_BOARD_PLATFORMS += canoe

# Kernel
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

# Kernel - prebuilt
TARGET_FORCE_PREBUILT_KERNEL := true
ifeq ($(TARGET_FORCE_PREBUILT_KERNEL),true)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
endif

# Kernel dtb/dtbo
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    abl \
    boot \
    dtbo \
    init_boot \
    mi_ext \
    odm \
    product \
    recovery \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vendor \
    vendor_boot \
    vendor_dlkm

# Assert
TARGET_OTA_ASSERT_DEVICE := pandora

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
# init_boot 也需要显式 header 版本，否则 soong 报
# "header_version: must be set"（build/soong/fsgen/Android.bp:41）
BOARD_INIT_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_INIT_BOOT_HEADER_VERSION)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 33554432

# Dynamic Partition
BOARD_SUPER_PARTITION_SIZE := 13421772800
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
# BOARD_QTI_DYNAMIC_PARTITIONS_SIZE=BOARD_SUPER_PARTITION_SIZE - 2MB
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 13419675648
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    product \
    odm \
    system_ext \
    vendor \
    vendor_dlkm

# System as root
# 原值 bluetooth dsp firmware persist：本设备树没有自带 sepolicy，
# e2fsdroid 会因 /bluetooth 找不到 SELinux 标签而中止 system.img 生成
# （set_selinux_xattr: No such file or directory searching for label "/bluetooth"）。
# system-only 移植下这些目录由 stock vendor 侧负责，system 不需要。
BOARD_ROOT_EXTRA_FOLDERS :=
BOARD_SUPPRESS_SECURE_ERASE := true

# File systems
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_COPY_OUT_VENDOR := vendor

# Recovery
# 本机 recovery.img 是**纯 ramdisk**，不含内核（kernel_size = 0）。
# 依据：能正常启动的 TWRP-3.7.1-xiaomi-sm8850-20260912-2.img 实测
#   header_ver=4  kernel_size=0  ramdisk 起始偏移 4096
# 内核由 ABL 从 boot 分区提供，recovery 分区只放 ramdisk。
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
# 不能带引号：soong 会把这个值直接写进 product_config JSON，
# 带引号会生成 ""RGBX_8888"" 导致 merge_json 解析失败
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
BOARD_RAMDISK_USE_LZ4 := true
BOARD_RECOVERY_RAMDISK_COMPRESS := lz4

# Display
TARGET_SCREEN_DENSITY := 520
TARGET_SCREEN_HEIGHT := 2656
TARGET_SCREEN_WIDTH := 1220
TW_FRAMERATE := 60

# Crypto - Keymaster not available in recovery on this device; disable to avoid boot hang
TW_INCLUDE_CRYPTO := false

# Tool
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_INCLUDE_LPDUMP := true
TW_INCLUDE_LPTOOLS := true

# TWRP Configuration
# Skip zip signature verification (Xiaomi OTA uses vendor keys, not otacerts)
TW_SKIP_DEFAULT_SIGNATURE := true
TW_THEME := portrait_hdpi
ifeq ($(TW_DEVICE_VERSION),)
TW_DEVICE_VERSION := 16.0
endif
# /data not mountable without crypto; use sideload or OTG for flashing
TW_NO_DATA_MEDIA := true
TARGET_RECOVERY_QCOM_RTC_FIX := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_NTFS_3G := true
TARGET_USES_MKE2FS := true
TW_USE_TOOLBOX := true
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
TW_MAX_BRIGHTNESS := 4095
TW_DEFAULT_BRIGHTNESS := 200
TW_SCREEN_BLANK_ON_BOOT := true
TW_EXCLUDE_APEX := true
TW_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone1/temp"
TW_BATTERY_SYSFS_WAIT_SECONDS := 5

# Debug
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# Serialno
TW_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true

# ── LineageOS recovery ────────────────────────────────────────────────
# recovery 的 init/fstab 放在 recovery/root/ 下，构建时会打进 ramdisk：
#   recovery/root/init.recovery.qcom.rc
#   recovery/root/init.recovery.usb.rc
#   recovery/root/system/etc/recovery.fstab
TARGET_RECOVERY_DEVICE_DIRS += device/xiaomi/pandora

# UI 边距（像素，不乘 density）。1220 宽下 52px ≈ 4.3%，接近 16dp。
TARGET_RECOVERY_UI_MARGIN_WIDTH := 52
TARGET_RECOVERY_UI_MARGIN_HEIGHT := 52

# ── 完整 ROM 分区配置（第一阶段新增） ────────────────────────────────
# 尺寸来自官方 payload 实测（tools/payload_dump.py --list）：
#   system 912457728  system_ext 710426624  product 4520914944
#   vendor 902373376  odm 3547955200  vendor_dlkm 54063104  system_dlkm 16912384
# 动态分区不写 BOARD_*IMAGE_PARTITION_SIZE（会与 super 分配冲突），只声明文件系统类型。
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4

# /metadata（metadata 加密、update_engine 快照都依赖它）
BOARD_USES_METADATA_PARTITION := true

# super 分区（12.5 GiB，与 stock 一致）
BOARD_SUPER_PARTITION_BLOCK_DEVICES := super
BOARD_SUPER_PARTITION_METADATA_DEVICE := super

# VINTF：system-only 移植用自己的宽松设备矩阵。
# 不能用 stock 的：它要求 framework 提供 vendor.qti.hardware.sigma_miracast_aidl
# 和 vendor.qti.qccsyshal_aidl，LOS 不构建这两个厂商扩展 HAL。
DEVICE_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml

# ── system-only 变体（第一阶段路径 A） ────────────────────────────────
# 只产出 system / system_ext / product，其余分区沿用 stock。
ifeq ($(TARGET_PRODUCT),lineage_pandora_sysonly)
TARGET_NO_KERNEL := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
# recovery 仍然要构建（system-only 刷机需要带 fastbootd 的 recovery），
# 因此这里不能设 TARGET_NO_RECOVERY，也不能清空
# BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE（否则 recovery 会带内核，本机 ABL 会拒绝）。
# stock 侧已有 vendor/odm/vendor_dlkm/system_dlkm，不构建这些镜像。
# 注意：BOARD_*IMAGE_FILE_SYSTEM_TYPE 不能置空，否则 board_config.mk:816 报
# "If TARGET_COPY_OUT_VENDOR_DLKM is ... must be set"。
endif
