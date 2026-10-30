
# ── 完整 ROM 追加配置（第一阶段新增） ────────────────────────────────
# 继承厂商 blob
$(call inherit-product-if-exists, vendor/xiaomi/pandora/pandora-vendor.mk)

# 设备侧 overlay / 权限
PRODUCT_PACKAGES += \
    DeviceAsWebcam

# 允许未实现的 HAL 依赖（bring-up 阶段）
PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := false

# 关闭需要 sm8850 CAF 源码才能提供的特性（当前源码树最高只到 sm8750）
TARGET_USES_QCOM_MM_AUDIO := false
