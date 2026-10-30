# 镜像发布说明

本目录只放说明文件，实际镜像通过 **GitHub Release** 分发。

GitHub 对单个 Release 附件有 2 GB 上限，因此 `super.img`（6.4 GB）需要切片上传。

---

## 一、镜像清单

| 文件 | 大小 | SHA256 |
|---|---|---|
| `system.img` | 892,424,192 B | `3569a1f9e7a777551d2c2de438e9041ed4ab16de8585cd418e415f02fb0faec1` |
| `system_ext.img` | 435,564,544 B | `a8f1c84a989b33ed4cd0fa0a504cdb9f9b505c41e8e6d0d17c7c8e75802beadd` |
| `product.img` | 509,595,648 B | `17d533be2c8c6d28d5f5074d34b1fec1ed7bbf2c2e5ead990d1535131fd28281` |
| `recovery.img` | 104,857,600 B | `740eedda7c3384e38e13b9337ffbad83f691dbe0d12a6b8594407568ec7230f9` |
| `super.img` | 6,448,791,536 B | `76bd8fe4a5fdfc49a8734ab446c3ac36055ced54ca12b0d9514888daa4012426` |

`recovery.img` 特性：
- `header_version = 4`，`kernel_size = 0`（内核由 ABL 提供，符合本机要求）
- 内置 `fastbootd`
- `ro.adb.secure = 0`，recovery 起来即免认证

---

## 二、super.img 合并

`super.img` 以 1.9 GB 分片上传，下载后需合并：

```bash
cat super.img.part* > super.img
sha256sum super.img
# 应等于 76bd8fe4a5fdfc49a8734ab446c3ac36055ced54ca12b0d9514888daa4012426
```

分片命名：`super.img.part00`、`super.img.part01`、`super.img.part02`、`super.img.part03`
（前 3 片各 1,992,294,400 B，末片 471,908,336 B；`cat super.img.part* > super.img` 已验证可还原）。

---

## 三、刷机

设备需解锁并进入 **bootloader fastboot**（关机后按住「电源 + 音量下」）。

### 方案 A：刷 super（推荐，一次性替换 8 个逻辑分区）

```bash
fastboot flash super super.img
fastboot --disable-verity --disable-verification flash vbmeta vbmeta-stock.img
fastboot reboot
```

`super.img` 内含：
`system` `system_ext` `product`（本项目编译）+
`mi_ext` `vendor` `vendor_dlkm` `system_dlkm` `odm`（原厂保持）。

### 方案 B：只替换 recovery（用于调试恢复环境）

```bash
fastboot flash recovery_a recovery.img
fastboot reboot recovery
```

### 还原原厂

```bash
# 用小米官方刷机包（pandora-ota_full-OS3.0.318.0.WBLCNXM）中的
# bin/windows/flash_all.bat，或手动：
fastboot flash super stock_super.img
fastboot flash vbmeta vbmeta-stock.img
```

---

## 四、已知问题

`super.img` 刷入后设备**未进入系统**，回落到原厂。首次启动失败点尚未定位，
需要 `logcat` 与 `/sys/fs/pstore` 分析。详见仓库根目录 `README.md`。

刷机前请确认已备份个人数据。
