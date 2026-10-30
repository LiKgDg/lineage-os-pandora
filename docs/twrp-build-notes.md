# TWRP 编译踩坑记录（twrp-16.0 / sm8850）

日期：2026-10-30
源码树：`/root/twrp`（`TWRP-Test/platform_manifest_twrp_aosp` @ twrp-16.0）
产物：`recovery.img` 104,857,600 B，SHA256 `7e54144e91bce151c757409d4b6311e41c02829799a196890420aaac6d9e42f0`

---

## 一、正确的编译命令

```bash
export JAVA_HOME=/root/twrp/prebuilts/jdk/jdk21/linux-x86
export PATH="$JAVA_HOME/bin:/root/twrp/prebuilts/build-tools/linux-x86/bin:$PATH"
source build/envsetup.sh
lunch twrp_sm8850-bp2a-eng
mka installclean
mka recoveryimage -j10
```

`lunch` 必须是**三段式** `<product>-<release>-<variant>`。

---

## 二、lunch 的 release 不是 trunk_staging

`build/release/release_configs/` 里只有：

```
ap2a  ap3a  ap4a  bp1a  bp2a  eng  root  user  userdebug
```

别名 `aosp_current → bp2a`。**没有 trunk_staging**，用它会 panic
`Missing config trunk_staging`。

另外 `build/release/build_config/` 下的 `DEFAULT=proto`、`trunk_staging=proto`、
`ap2a=make` 这些**带等号的文件名不是 bug**，是 `release_config.mk:120`
用来判断走 protobuf 还是 make 路径的标记文件，不要改名。

---

## 三、repo sync 在这棵树上不工作

现象：`repo sync` 秒退、无输出、工作区不产生文件，但 `project-objects`
里已有几十 GB 对象。

根因：拉取在「写 ref + 建 `.repo/projects` + checkout」之前被打断，
repo 认为已同步。`.repo/projects/<name>.git` 不存在、`show-ref` 为空。

绕过：直接 `git fetch --depth=1` + `--work-tree` 检出，见
`scripts/maintain/fetch_missing_projects.py`。

---

## 四、镜像源

| 源 | 状态 |
|---|---|
| TUNA `mirrors.tuna.tsinghua.edu.cn/git/AOSP` | **排队严重**（排到 30+ 位），不适合大仓库 |
| BFSU `mirrors.bfsu.edu.cn/git/AOSP` | **即时响应**，首选 |
| NJU | 路径不存在 |
| googlesource 直连 | 能 ls-remote，大 packfile 易被中间人代理截断 |

`prebuilts/clang` 28 GB、`prebuilts/build-tools` 33 GB、`frameworks/base` 3 GB
都是从 BFSU 拿的，55 秒到几分钟。

GitHub 上的 TWRP 仓库（`android_frameworks_base`、`android_system_extras`）
`git clone` 报 `fatal: expected 'packfile'`，是 SteamTools 中间人代理截断大包；
镜像站 ghproxy / kkgithub / bgithub 全部无响应。可行做法是 tarball 直下
（`codeload.github.com/.../archive/refs/heads/twrp-16.0.tar.gz`）或直接用
BFSU 的 AOSP 版本（模块定义一致，TWRP 分支只多几个补丁）。

---

## 五、缺项目导致的 soong panic（连锁）

补 `frameworks/base` 之前，soong bootstrap 会因模块定义缺失连续 panic：

```
1) AdServicesSharedLibrariesUnitTestsRavenwood
   runtime error: index out of range [0] with length 0
   build/soong/java/ravenwood.go:190
   → ctx.GetDirectDepsProxyWithTag(ravenwoodUtilsTag)[0] 未判空

2) libaconfig_android_hardware_biometrics_rust
   Exactly one aconfig_declarations property required
   build/soong/aconfig/codegen/rust_aconfig_library.go:66
```

两者根因相同：`frameworks/base` 缺失导致 aconfig 声明与 ravenwood utils 找不到。
补上 `frameworks/base` 后自动消失。

临时兜底可用 `scripts/maintain/patch_ravenwood_guard.py`（加空数组保护），
依赖补齐后 `--revert` 还原。

---

## 六、se_omapi 缺 recovery 变体

```
FAILED: .../se_omapi/android_recovery_arm64_armv8-a/unstripped/se_omapi
module se_omapi missing dependencies:
  android.se.omapi-V1-ndk{os:android,image:recovery,link:shared}
```

设备树里 `TW_INCLUDE_OMAPI := true` 会引入 `se_omapi`，而
`android.se.omapi-V1-ndk` 没有 recovery 变体。改为 `false` 即可，
OMAPI（NFC 安全元件）在 recovery 里基本用不到。

---

## 七、ccache 与文件系统只读

一次构建中 ccache 报：

```
ccache: error: failed to create temporary file
  for /root/.ccache/tmp/...: Read-only file system
```

连锁导致 `external/icu`、`external/sqlite` 等全部失败。

两个诱因：
1. **WSL 默认用户从 root 变成 msi(uid 1000)**，写不了 root 所有的目录
   → 统一用 `wsl -d Ubuntu-24.04 -u root`
2. WSL VM 在 `-j16` 下重启，`errors=remount-ro` 触发只读

处理：`-j` 降到 10，首次全量编译**关闭 ccache**（缓存为空，纯增加写入）。

---

## 八、镜像结构校验（刷机前必做）

```bash
python3 -c "
import struct
d=open('recovery.img','rb').read(64)
print('magic', d[:8])
print('kernel_size', struct.unpack('<I', d[8:12])[0])
print('header_version', struct.unpack('<I', d[40:44])[0])
"
```

期望：

| 项 | 值 | 说明 |
|---|---|---|
| magic | `ANDROID!` | |
| kernel_size | **0** | `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true` |
| header_version | **4** | 本机 ABL 要求 |
| 大小 | 104,857,600 | `BOARD_RECOVERYIMAGE_PARTITION_SIZE` |

ramdisk 内应存在 `system/bin/twrp`（51 KB）和 `system/bin/fastbootd`（2.1 MB）。
`sbin/recovery` 在 staging 里没有，是 TWRP 启动时自己放进去的。

`vendor/lib/modules/1.1/` 里 0 个 `.ko` 属正常：TWRP 的
`kernel_module_loader.cpp` 会在运行时从挂载的 `/vendor/lib/modules/N.N`、
`/vendor_dlkm/lib/modules` 加载，触摸驱动从 stock 的 vendor_dlkm 取。

---

## 九、运行验证结果

| 项 | 结果 |
|---|---|
| adb | `fd3af370 recovery product:pandora model:Xiaomi_17_Pro` |
| `ro.twrp.version` | `3.7.1_16-Xiaomi_17_Pro` |
| fingerprint | `Xiaomi/twrp_sm8850/sm8850:99.87.36/BP2A.250605.031.A2/eng.root:eng/test-keys` |
| `/sbin/recovery` | 3,337,936 B |
| recovery.fstab | 8 个逻辑分区全部识别 |
| 触摸驱动 | `syna_tcm_enable_touch_raw: en:1`，`xiaomi_touch_mode` 正常 |
| dmesg | 无 panic |
