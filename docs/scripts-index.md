# 脚本索引

> 由 `scripts/maintain/selfcheck.sh --index` 自动生成，请勿手改。
> 说明取自文件头的首行注释。

## scripts/build

| 脚本 | 说明 |
|---|---|
| `build_los_gated.sh` | build_los_gated.sh —— 带 KMI 门禁的 LOS 构建入口 |
| `build_recovery_fb.sh` | build_recovery_fb.sh —— 临时改写 BoardConfig.mk 的 recovery 开关，用于单独编 recovery |
| `build_sysonly.sh` | build_sysonly.sh —— 只编 system 镜像的构建入口（lunch lineage_pandora_sysonly） |
| `build_twrp.sh` | TWRP recovery 前台编译脚本 —— 在 GUI 终端里运行可看到 ninja 实时进度条 |
| `los_sync.sh` | 初始化并同步 LineageOS 24.0 源码树，供 sm8850 完整 ROM 开发使用。 |
| `lunch_sysonly.sh` | lunch_sysonly.sh —— 切到 sysonly 变体的 lunch 目标并导出环境 |
| `make_fastboot_package.sh` | make_fastboot_package.sh —— 生成 `fastboot -w update` 可直接消费的整包 |
| `make_pandora_kernel.sh` | 从 pandora 的 stock 分区镜像组装 device/xiaomi/pandora-kernel |
| `make_pandora_kernel_a17.sh` | 从 pandora 的 A17 stock 分区镜像组装 device/xiaomi/pandora-kernel |
| `twrp_sync.sh` | 初始化并同步 TWRP (twrp-16.0) 源码树。可反复执行，repo sync 是增量的。 |
| `twrp_sync_groups.sh` | 补齐 manifest 组（pdk 组含 prebuilts/clang、prebuilts/build-tools 等构建必需项） |

## scripts/device

| 脚本 | 说明 |
|---|---|
| `apply.sh` | apply.sh —— 把 staging/ 下的配置改动同步进 device/xiaomi/pandora |
| `apply_sysonly.sh` | apply_sysonly.sh —— 同上，作用于 sysonly 变体的 device 树 |
| `patch_sysonly.py` | Apply system-only port patches to the pandora device tree. |
| `rebuild_blobs_a17.sh` | 用 A17 (OS4.0.5.0) blobs 重建 vendor/xiaomi/sm8850-common |
| `rebuild_blobs_a17_surgical.sh` | 保持 A16 的文件选择范围，二进制替换为 A17 版本 |
| `update_to_a17.py` | 把设备树中 A16（OS3.0.318.0 / 6.12.23）配置更新为 A17（OS4.0.5.0 / 6.12.69）。 |

## scripts/dt

| 脚本 | 说明 |
|---|---|
| `extract_pandora_dt.sh` | extract_pandora_dt.sh —— 从原厂 boot/vendor_boot/dtbo 提取设备树（pandora-dt 的早期版本） |

## scripts/flash

| 脚本 | 说明 |
|---|---|
| `backup_partitions.sh` | 备份 pandora 关键分区到 PC |
| `build_stock_super.sh` | 用原厂 A17 逻辑分区打包 super.img（仅 slot A） |
| `flash_fastboot_package.sh` | flash_fastboot_package.sh —— 刷 fastboot 整包（fastboot -w update） |
| `flash_fastbootd.sh` | 刷入 pandora LineageOS 镜像（fastbootd） |
| `flash_kernel_a17.sh` | flash_kernel_a17.sh —— 逐分区刷 A17 内核相关的 5 个分区（boot dtbo vendor_boot vendor_dlkm sy |
| `flash_los_full.sh` | fastbootd 模式一次性刷入 LOS 全部 13 个分区 |
| `flash_los_noverify.sh` | 测试：LOS 全量 + 两个 vbmeta 都关闭校验 |
| `flash_los_stage1.sh` | 阶段 1：bootloader 模式刷物理分区 |
| `flash_los_with_recovery.sh` | 补齐 LOS 物理分区（含 recovery），凑齐完整 AVB 签名集 |
| `flash_super.sh` | system-only 刷机：super.img 路线（设备需在 bootloader fastboot 模式） |
| `flash_sysonly.sh` | system-only 刷机流程（设备需先在 bootloader fastboot 模式） |
| `make_super.sh` | make_super.sh —— 用 lpmake 把动态分区打包成 super.img |
| `restore_stock_a17.sh` | 恢复 pandora 原厂 A17 物理分区 |
| `restore_stock_full.sh` | 完整恢复 pandora 原厂 A17：物理分区 + super（逻辑分区） |

## scripts/maintain

| 脚本 | 说明 |
|---|---|
| `add_include.py` | 给 C++ 源文件补标准头文件（新版 libc++ 取消传递包含后的常见修复）。 |
| `backup_los_tree.sh` | backup_los_tree.sh —— 把已同步的 LOS 设备/厂商树备份到 backup/ |
| `check_twrp_tree.sh` | check_twrp_tree.sh —— 检查 TWRP 树的关键路径是否齐全 |
| `clean_stale_modules.sh` | 清理 out/target/product/pandora 下混入旧世代模块的残留暂存 |
| `clean_wsl_temp.sh` | 清理可再生的临时产物（不涉及 out/ 与备份） |
| `cleanup_disk.sh` | 回收 Ubuntu 磁盘空间：移除构建不需要的 CTS、临时目录与缓存。 |
| `drop_conflicting_blobs.py` | 从 blob 包中剔除与 AOSP 自编译模块冲突的文件。 |
| `drop_modules_by_name.py` | 按模块名从 blob 包中剔除对应文件。 |
| `drop_paths.py` | 按相对路径清单（如 vendor/bin/wpa_cli）从 blob 包剔除文件。 |
| `dump_device.sh` | dump_device.sh —— 从设备侧取 dump 的两种方式（B: adb pull / C: 分区 dd） |
| `extract_blobs_from_ota.sh` | extract_blobs_from_ota.sh —— 从原厂 OTA 解出的分区镜像补齐 vendor blobs |
| `extract_crash_logs.sh` | extract_crash_logs.sh —— 从设备分区里取崩溃/启动日志 |
| `fetch_missing_projects.py` | 补齐 TWRP 源码树中缺失的项目。 |
| `find_missing_projects.sh` | 列出 manifest 中声明但工作区不存在的项目路径。 |
| `fix_blob_deps.py` | 移除 Xiaomi blob 包里 libwfdcommonutils 对 libdng_sdk 的虚假依赖。 |
| `fix_citsensor_prebuilt.py` | 让 alsd 能找到 citsensors AIDL 头。 |
| `fix_ipa_headers.py` | 修复预编译内核设备上 libipanat / ipacm 找不到 linux/msm_ipa.h。 |
| `fix_qcwcn_common.py` | 修复 lib_driver_cmd_qcwcn 的 drv/bss 重复符号。 |
| `fix_recovery_algorithm.py` | 修复 bootable/recovery/volume_manager/PublicVolume.cpp 缺少 <algorithm>。 |
| `fix_rildb_filegroups.py` | 为 A17 blob 包补 qcril 数据库 SQL 的 filegroup。 |
| `fix_sepolicy_compat.py` | 为 treble_sepolicy_tests_202604 补 SELinux 兼容性忽略清单。 |
| `fix_wfd_elfcheck.py` | 修复 libwfdcommonutils 的 check_elf_file 失败。 |
| `install_ca.sh` | install_ca.sh —— 把 staging 里的自定义 CA 证书转换并安装进系统信任库 |
| `kmi-gate.sh` | kmi-gate.sh —— 构建期 KMI 一致性门禁 |
| `los_fill_missing.py` | 补齐 LineageOS 源码树中未检出的项目。 |
| `patch_cmdline_diag.sh` | patch_cmdline_diag.sh —— 给内核 cmdline 追加「把挂死变成崩溃」的诊断参数 |
| `patch_manifest_stub.py` | 让 build-manifest.xml 的生成在 .repo 不可用时降级，而不是硬失败。 |
| `patch_ravenwood_guard.py` | 给 build/soong/java/ravenwood.go 的空依赖索引加保护。 |
| `probe_adb_host.sh` | 探测 WSL 到 Windows adb server 的可用地址 |
| `pull_lfs_objects.sh` | 拉取源码树里所有 Git LFS 对象。 |
| `regen_makefiles.sh` | regen_makefiles.sh —— 带闸的 setup-makefiles 包装器 |
| `repair_index.sh` | 修复索引被清空的项目：git reset --hard HEAD |
| `replace_kernel_modules.sh` | replace_kernel_modules.sh —— 内核模块「整目录替换」（KMI 世代对齐） |
| `selfcheck.sh` | selfcheck.sh —— 仓库自检：语法 / 换行 / 元数据 / 文档覆盖 |
| `setup_wsl_adb.sh` | 在 WSL 内安装 adb 并指向 Windows 的 adb server（镜像网络模式，走回环地址） |
| `split_dtb.py` | 把 vendor_boot 里的拼接 dtb 拆成单个 dtb 文件。 |
| `toggle_vendor.py` | 批量开关 Android.bp 中指定模块的 vendor_available。 |
| `verify_index_ref.sh` | verify_index_ref.sh —— 「整目录替换」验收：三处模块目录与参考构建逐字节相同 |
| `verify_kernel_modules.sh` | 刷机前静态校验：构建产物里的内核模块必须与内核同属一个 KMI 世代 |

## scripts/patch

| 脚本 | 说明 |
|---|---|
| `apply_rcmode_patch.sh` | apply_rcmode_patch.sh —— 把 rc-mode 二进制装进 recovery/root/system/bin |
| `patch_usb_ordering.py` | Add deterministic USB mode-switch ordering to init.recovery.qcom.rc. |
| `patch_usb_reenum.py` | Patch init.recovery.usb.rc so every USB config switch re-enumerates. |

## tools

| 脚本 | 说明 |
|---|---|
| `gen_blob_list.py` | Generate a LineageOS-style proprietary blob package from stock partition trees. |
| `gen_vendor_bp.py` | Generate a soong (Android.bp) blob package from proprietary-files.txt. |
| `gen_vendor_mk.py` | Generate Android.mk / pandora-vendor.mk / BoardConfigVendor.mk for a blob packag |
| `payload_dump.py` | Minimal Android OTA payload.bin dumper (A/B full & incremental). |

