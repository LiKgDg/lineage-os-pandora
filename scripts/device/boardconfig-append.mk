
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

# VINTF：允许与 stock vendor 的 manifest 做宽松匹配
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml
DEVICE_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml
