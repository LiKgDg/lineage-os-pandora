# LineageOS 24.0 源码树搭建踩坑记录（sm8850 / pandora）

日期：2026-10-31
源码树：`/root/los24`，`lineage-24.0`（Android Baklava / CP2A）
设备：Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）

---

## 一、正确的初始化方式

```bash
mkdir -p /root/los24 && cd /root/los24
repo init -u https://github.com/LineageOS/android.git \
    -b lineage-24.0 \
    -g default,pdk,platform-linux \
    --repo-url=https://github.com/GerritCodeReview/git-repo \
    --repo-rev=main --no-repo-verify
repo sync -c -j8 --no-clone-bundle
```

---

## 二、坑 1：`-g` 必须加在 `init` 上

`repo sync -g default,pdk,platform-linux` **不会改变已生效的组**。
组是在 `repo init` 时写进 `.repo/` 状态的，加在 `sync` 上等于没加。

验证：

```bash
repo info | grep "Manifest groups"
# 期望：default,pdk,platform-linux
```

不加 `pdk` 组的后果：`system/sepolicy`、`prebuilts/clang`、`prebuilts/misc`、
`frameworks/base` 全部被跳过，编译时 soong bootstrap 直接失败：

```
hardware/interfaces/compatibility_matrices/build/Android.bp:24:1:
  "vintf-compatibility-matrix-soong-rules" depends on undefined module "soong-selinux"
```

---

## 三、坑 2：`repo sync` 会静默漏项目

即使组对了、`-j8` 跑满时间、树体积涨到 180 GB、项目数上千，
仍有大量项目**根本没检出**，而且**不报任何错**。

实测：manifest 共 **1400** 个项目，跑完几轮后仍缺 **363** 个（排除 GKI 内核树后 205 个）。

更麻烦的是 `repo list` 只列**启用 group** 的项目，被 group 过滤的连列都不列，
所以「manifest vs 磁盘」的对比脚本也扫不出来。

**解法**：直接解析 manifest XML，绕开 `repo list`。

```bash
python3 scripts/maintain/los_fill_missing.py /root/los24 --dry-run   # 报告
python3 scripts/maintain/los_fill_missing.py /root/los24 --sync      # 批量补
```

脚本解析 `.repo/manifests/default.xml` + `snippets/*.xml`，默认排除
`kernel/platform/`（GKI 内核源码树，本设备用预编译内核，不需要）。

---

## 四、坑 3：D 盘被 vhdx 吃满导致 WSL I/O 错误

现象：

```
<3>WSL (4518 - Relay) ERROR: CreateProcessCommon:817:
  execvpe(/bin/bash) failed: I/O error
```

连 `/bin/bash` 都执行不了，看起来像文件系统损坏。

**真因**：`D:\WSL\Ubuntu-24.04\ext4.vhdx` 涨到 446 GB，D 盘只剩 10.6 GB。
WSL 写入失败，表现成 I/O 错误。

**注意 `df` 会骗人**：WSL 内 `df -h /` 显示 1007 GB 虚拟容量、还剩几百 GB，
那是 ext4 的虚拟上限，和 Windows 实际磁盘无关。

**排查顺序**：

1. Windows 侧看真实空间：`Get-PSDrive D`
2. 看 vhdx 实际大小：`(Get-Item 'D:\WSL\...\ext4.vhdx').Length / 1GB`
3. 两者对不上就是 vhdx 膨胀

**处理**：

```powershell
wsl --shutdown
# 等 vmmem 完全退出
diskpart /s compact.txt
# compact.txt:
#   select vdisk file="D:\WSL\Ubuntu-24.04\ext4.vhdx"
#   attach vdisk readonly
#   compact vdisk
#   detach vdisk
#   exit
```

本次实测：删掉 209 GB 的 TWRP 源码后，compact 把 vhdx 从 446.2 → **243.3 GB**，
D 盘可用从 10.6 → **213.5 GB**。

**教训**：删除大目录后必须 compact，vhdx 不会自动缩。

---

## 五、坑 4：`hardware/qcom-caf/sm8850` 其实是存在的

早期判断「LOS 没有 sm8850 CAF」是**错的**。错在方法：

```bash
git ls-remote https://github.com/LineageOS/android_hardware_qcom-caf_sm8850
# → Not Found
```

LineageOS 的 CAF 仓库只在自家 Gerrit（review.lineageos.org）上，
GitHub 镜像不全。manifest 指向 Gerrit，`repo sync` 能正常拉到。

树里实际有：

```
hardware/qcom-caf/  bootctrl common msm8953 sdm660 sm8150 sm8250 sm8350
                    sm8450 sm8450-6.6 sm8550 sm8650 sm8750 sm8850 thermal wlan
```

`sm8850` 116 MB，含 `Android.bp` / `audio/` / `dataipa/` / `display/`，
连 `audio/primary-hal/configs/canoe/` 的音频配置都齐。

**结论**：不要用「GitHub 上有没有」来判断 LOS 有没有某个仓库。

---

## 六、坑 5：lunch 必须三段式

```bash
lunch lineage_pandora-userdebug            # ✗ Invalid lunch combo
lunch lineage_pandora-trunk_staging-userdebug   # ✓
```

可用的 release：`ap2a ap3a ap4a bp1a bp2a bp3a bp4a cp1a cp2a trunk_staging`
加 `eng` / `user` / `userdebug` / `root`。

成功输出：

```
LINEAGE_VERSION=24.0-20261030-UNOFFICIAL-pandora
TARGET_PRODUCT=lineage_pandora
TARGET_BUILD_VARIANT=userdebug
PLATFORM_VERSION_CODENAME=Baklava
BUILD_ID=CP2A.260605.016
```

---

## 七、依赖仓库清单

| 路径 | 来源 | 状态 |
|---|---|---|
| `device/xiaomi/sm8850-common` | `lolipuru/android_device_xiaomi_sm8850-common` @ lineage-24.0 | 上游，标注 booted |
| `vendor/xiaomi/sm8850-common` | `lolipuru/android_vendor_xiaomi_sm8850-common` | blobs |
| `device/xiaomi/popsicle` | `lolipuru/android_device_xiaomi_popsicle` | 参考机型树 |
| `hardware/qcom-caf/sm8850` | LOS Gerrit（manifest 自带） | 116 MB 完整 |
| `device/xiaomi/pandora` | 自建（`device-trees/los24-pandora/`） | 骨架 |

注意：`sm8850-common` 支持 pudding / popsicle / myron / athens / songyuan，
**不含 pandora**。pandora 的机型树要自己写。

---

## 八、pandora 机型参数（从设备实测）

```
Physical size      : 1220x2656
Physical density   : 520          → TARGET_SCREEN_DENSITY := 520
ro.product.model   : 25098PN5AC
ro.product.device  : pandora
ro.board.platform  : canoe
fingerprint        : Xiaomi/pandora/pandora:16/BP2A.250605.031.A3/OS3.0.318.0.WBLCNXM:user/release-keys
```

popsicle 的 density 是 480，pandora 是 520，**不能照抄**。

---

## 九、内核

`sm8850-common` 的 `BoardConfigCommon.mk` 提交说明：
「allow opt-in to build kernel from source — currently, only pudding and myron are supported」

→ popsicle / pandora 默认走**预编译内核**，不需要编内核源码。

机型树里 `KERNEL_PATH := $(DEVICE_PATH)-kernel`，即需要独立仓库
`device/xiaomi/pandora-kernel`，内含 kernel / dtbo.img / dtb/ / vendor_ramdisk/ /
vendor_dlkm/ / system_dlkm/，从 stock OTA 提取。

lunch 输出里的 `PRODUCT_SOURCE_ROOT_DIRS=-kernel/platform` 说明构建系统
还期望该仓库下有 `platform/` 子目录。

### 实测结论（2026-10-31）

| 项 | pandora | popsicle | 结论 |
|---|---|---|---|
| `uname -r` | `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k` | 同 | GKI 内核相同 |
| `kernel` sha256 | `4441e484…8e35c8` | 同 | **字节级一致** |
| `dtbo.img` | 23,068,672 B / `8ab9f935…` | 23,068,672 B / `ba90f6c4…` | 大小同、内容不同，**板级专属** |
| `dtb` 拼接 | 4,509,446 B | 4,511,568 B | 略有差异，用 pandora 自己的 |
| `vendor_dlkm` | 54,063,104 B / 374 个 .ko | 122 MB | **差异很大**，不能复用 |

所以内核仓库必须从 pandora 自己的 stock 提取，不能拿 popsicle 的顶替——
`vendor_dlkm` 里是触摸、显示等机型驱动。

组装脚本：`scripts/build/make_pandora_kernel.sh`，产出 262 MB，包含

```
kernel                39,963,136 B
dtbo.img              23,068,672 B
dtb/                  8 个，拼接后与原 dtb 段字节一致
vendor_ramdisk/       416 个 .ko + modules.load(.recovery)
vendor_dlkm/          374 个 .ko + modules.load
system_dlkm/          15 项（含 kernel/ 与 modules.* 元数据）
system_dlkm_flatten/  103 个 .ko
```

---

## 十、坑 6：`repo sync` 留下被清空的 git 索引

`external/deqp` 的表现：

```
git ls-files        → 0
磁盘文件             → 4651
git ls-tree HEAD    → 8196
```

索引被清空、磁盘少 3545 个文件，soong 报
`module source path "external/deqp/framework/delibs/debase" does not exist`。

全树扫描（`repo forall` 统计 `ls-files` 为 0 的项目）共 8 个，
其中 7 个本来就是空仓库，只有 deqp 受损。修复：

```bash
git -C external/deqp reset --hard HEAD     # 索引 0 -> 8196，文件全部恢复
```

脚本：`scripts/maintain/repair_index.sh`（默认 dry-run，传参才执行）。

---

## 十一、坑 7：blob 包过度声明依赖导致 vendor 变体级联

现象是一串「missing variant: os:android,image:vendor」错误，依次是
`libskia_skcms` → `libhwy` → `xmp_toolkit_sdk` → `zuid_md5`。

根因不在 AOSP，而在 `vendor/xiaomi/sm8850-common/Android.bp`：
`libwfdcommonutils` 的 `shared_libs` 是从 `.so` 的 `DT_NEEDED` 全量导出的
（连 `libc`、`libm` 都在），其中包含 `libdng_sdk`。该模块是
`system_ext_specific`，system_ext 依赖 `vendor_available` 库时会解析到
**vendor 变体**，于是触发整条链。

**给提供方补 `vendor_available` 会无限级联**（实测补完一个冒下一个），
正确做法是在消费方摘掉这条不存在的依赖：

```bash
python3 scripts/maintain/fix_blob_deps.py
```

工具：`scripts/maintain/toggle_vendor.py` 可批量开关任意模块的
`vendor_available`，用于验证「到底有没有人需要 vendor 变体」。

---

## 十二、坑 8：`GOMEMLIMIT` 对 soong_build 无效

`soong_build` 在 1400 个项目的全量树上 RSS 会涨到 22 GB 以上，
24 GB 的 WSL 直接进 swap 抖动，`m nothing` 跑 20 分钟不结束。

尝试用 `GOMEMLIMIT=13GiB` 约束 Go 堆，**无效**。原因在构建命令行本身：

```
env -i "$BUILDER" --top ... --available_env out/soong/soong.environment.available ...
```

`env -i` 会清空环境，soong_build 只认 `--available_env` 里列出的变量，
命令行导出的 `GOMEMLIMIT` 传不进去。

实际可行的做法：

- 给 WSL 加大内存（`.wslconfig` 的 `memory=`），或
- 接受一次性的高内存峰值，别中途 kill（RSS 涨到 22 GB 后会回落，说明已过峰值），或
- 精简树里用不到的模块（cts、deqp 等）以减少 soong 分析量

判断是否在真跑而不是纯抖动：看 `%CPU`，超过 200% 说明在多线程推进。

---

## 十三、D2 通过（2026-10-31 10:44）

```
[100% 43/43] nothing
Successfully read the makefiles.
ninja:  6.10s Build Succeeded: 1 steps - 0.16/s
#### build completed successfully (30:07 (mm:ss)) ####
```

0 个 `FAILED`，0 个 `error`。soong 全量分析 + kati 读 makefile 全部通过。

### 第 4 类问题的细节

上一轮卡在 kati：

```
vendor/lineage/build/tasks/kernel.mk:140: error: Argument missing.
```

第 140 行是 `ifeq ($(call is-version-greater-or-equal,$(TARGET_KERNEL_VERSION),5.15),true)`，
`TARGET_KERNEL_VERSION` 为空导致 `call` 缺参数。

该变量只在 `sm8850-common/BoardConfigCommon.mk:108` 定义，而它位于

```makefile
ifeq ($(TARGET_OPT_IN_OSS_KERNEL),true)
    TARGET_KERNEL_VERSION := 6.12
endif
```

即「用 OSS 源码编内核」的分支。我们用预编译内核，分支不执行，变量为空。

而 `kernel.mk:140` 又位于 `ifneq ($(TARGET_NO_KERNEL_OVERRIDE),true)` 块内（第 106 行起），
本应由 `TARGET_NO_KERNEL_OVERRIDE := true` 跳过。这个变量在 pandora 的 `BoardConfig.mk`
里是有的，但被 `ifneq ($(wildcard $(KERNEL_PATH)/kernel),)` 守卫——`pandora-kernel`
没部署时守卫不成立，变量没设，于是走进 140 行。

**所以根因不是缺变量，是内核仓库没就位。** 部署 `device/xiaomi/pandora-kernel` 后，
`wildcard` 成立 → `TARGET_NO_KERNEL_OVERRIDE := true` → 整个块被跳过 → 错误消失。

### D3 的阻塞

D3（`mka bacon`）预计需要 `out/` 再涨 60–80 GB，而 D 盘只剩 13.7 GB
（vhdx 436.5 GB / 总 500 GB）。必须先解决空间，见磁盘方案。

---

## 十四、`.repo` 迁移到独立虚拟磁盘（2026-10-31 12:52）

### 为什么必须搬

D 盘总 500 GB，`ext4.vhdx` 437 GB，`.repo` 独占 290 GB，`out/` 还要再涨 80 GB。
清理临时文件只能腾出 1 GB，compact 也只能回收 4 GB（425 vs 429，空洞极小）。

而且**不能简单删 `.repo`**——`vendor/lineage/build/tasks/build-manifest_xml.mk:21`
会在构建时执行：

```makefile
REPO_TRACE=0 python3 .repo/repo/repo manifest -o - -r | grep -Ev "proprietary_..." > $@
```

删掉 `.repo` 会让 `mka bacon` 在生成 build-manifest 时失败。

### 做法

| 步骤 | 操作 |
|---|---|
| 1 | `diskpart` 在 `E:/WSL/los24-repo.vhdx` 建 300 GB 动态 VHD（需管理员） |
| 2 | `wsl --mount --vhd ... --bare` 附加（需管理员），出现 `/dev/sde` |
| 3 | `mkfs.ext4 -L los24repo /dev/sde`，挂到 `/mnt/los24-repo` |
| 4 | `rsync -aHAX --numeric-ids` 复制 `.repo`，约 36 分钟 |
| 5 | 校验字节数一致（310,721,610,351 对 310,721,610,351） |
| 6 | 原 `.repo` 改名 `.repo.old`，`mount --bind /mnt/los24-repo /root/los24/.repo` |
| 7 | 验证 `repo list`（1246）与 `repo manifest -r`（1287 行） |
| 8 | 删 `.repo.old`，WSL 内部 433 GB → **143 GB** |

`/etc/fstab` 新增（UUID 由 `blkid` 取得）：

```
UUID=20f171fd-23e4-4f48-b48b-8fe358041783 /mnt/los24-repo ext4 defaults,nofail 0 2
/mnt/los24-repo /root/los24/.repo none bind,nofail 0 0
```

### 运维注意

`wsl --mount --vhd` 的附加**不会跨 WSL 重启保留**。脚本 `scripts/maintain/compact-disk.cmd`
（管理员）会依次做：关闭 WSL → compact vhdx → 启动 WSL → 重新附加 VHD → `mount -a` → 校验。
**每次 `wsl --shutdown` 之后都要跑一次**，否则 `.repo` 为空、构建会在 manifest 步骤失败。

`fstab` 里用了 `nofail`，所以 VHD 未附加时不会阻塞启动，但 `.repo` 会是空目录。

---

## 十五、git 推送失败：环境变量里的代理端口是错的

现象：

```
fatal: unable to access 'https://github.com/...': CONNECT tunnel failed, response 502
```

排查结果：

| 项 | 值 |
|---|---|
| 环境变量 `http_proxy` | `http://127.0.0.1:52728`（**失效**） |
| 实际可用代理 | `http://127.0.0.1:7890`（curl 走它返回 200） |
| 直连 github | 超时（`000`） |

`git` 默认读取环境变量里的代理，于是打到已经关闭的 52728 端口。

**解决**：给仓库设置正确的代理端口，绕过环境变量。

```bash
git config http.proxy http://127.0.0.1:7890
```

注意该端口随代理工具启动而变，若再次 502，先确认当前可用端口：

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 -x http://127.0.0.1:7890 https://github.com
```

---

## 十六、误杀 wslservice 导致 vhdx 句柄泄漏（事故复盘）

### 现象

为了给 `diskpart compact` 腾出文件锁，执行了：

```
taskkill /F /PID <wslservice>
taskkill /F /PID <vmcompute>
```

结果 WSL 彻底起不来：

```
ERROR_SHARING_VIOLATION
Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_SHARING_VIOLATION
```

`Get-Disk` 里残留一个 1024 GB 的 `Msft Virtual Disk`（即 `ext4.vhdx` 的虚拟容量），
文件被独占锁住。`diskpart detach`、`Dismount-DiskImage` 均无效
（后者返回「成功」但实际没有卸载）。

### 根因

WSL 3.x 把发行版 vhdx 以虚拟磁盘形式挂在 Windows 存储栈上（`\\.\PhysicalDrive3`）。
正常关闭时由 `wslservice` 与 HCS 负责 detach；**直接杀进程会跳过清理**，
留下孤立挂载，文件锁再没人释放。

### 唯一解

**重启 Windows**。重启后遗留挂载消失，vhdx 从 437.2 GB 降到 318.4 GB（部分回收），
D 盘可用从 12.7 GB 回到 133.3 GB。

### 正确做法

不要杀服务。用 `scripts/maintain/compact-disk.cmd`（管理员），它的顺序是：

```
wsl --shutdown  ->  diskpart attach readonly / compact / detach  ->  启动 WSL  ->  附加 .repo VHD  ->  mount -a
```

`wsl --shutdown` 走正常清理路径；杀进程不会。

---

## 十七、`.cmd` 脚本必须用 CRLF

`.gitattributes` 里 `* text=auto eol=lf` 会把 `.cmd` 也规范成 LF。
批处理文件用 LF 行尾时，`if %errorLevel% neq 0 (` 这类多行块会被 cmd.exe 解析错，
表现就是双击没反应、或窗口一闪而过。

已修正：

```
*.cmd   text eol=crlf
*.bat   text eol=crlf
*.ps1   text eol=crlf
```

两个脚本同时改写成纯 ASCII 输出。原因有二：

1. `chcp 65001` 配合中文输出在部分终端会乱码
2. 全角引号 `“ ”` 在脚本宿主里会被当成字符串定界符，直接引发语法错误

---

## 十八、`.repo` 缺失时的构建降级

`.repo` 搬到独立 VHD 后，若 VHD 未附加，`fstab` 的 bind mount 会落到同名空目录上
（`nofail` 不报错），于是 `.repo` 是空的，`repo manifest -r` 失败。

补丁 `scripts/maintain/patch_manifest_stub.py` 把 `build-manifest_xml.mk` 的 recipe 改成：

```makefile
@if [ -x .repo/repo/repo ] && [ -d .repo/project-objects ]; then \
    REPO_TRACE=0 python3 .repo/repo/repo manifest -o - -r | grep ... > $@; \
else \
    echo "WARNING: .repo unavailable, writing stub build-manifest.xml" >&2; \
    printf ... > $@; \
fi
```

这样 `.repo` 不可用时写占位 XML 并告警，而不是让整个 `mka bacon` 失败。
代价是 ROM 里的 `build-manifest.xml` 不含真实源码版本信息，个人使用无影响。

还原：`python3 scripts/maintain/patch_manifest_stub.py --revert`

---

## 十九、D3 编译期缺头文件（libc++ 取消传递包含）

LOS 24 用的 libc++ 移除了传递包含，一批老代码里「靠别的头文件带进来」的标准库符号开始报错。
D3 分三轮暴露出来：

| 轮次 | 失败点 | 报错 | 修复 |
|---|---|---|---|
| 1 | `bootable/recovery/volume_manager/PublicVolume.cpp:65` | `no member named 'replace' in namespace 'std'` | 补 `<algorithm>` |
| 2 | `vendor/qcom/opensource/vibrator/aidl/VibratorSelector/VibratorSelector.cpp:43` | `implicit instantiation of undefined template 'std::shared_ptr<VibratorSelector>'` | 补 `<memory>`、`<vector>` |
| 4 | `system/vold/model/PublicVolume.cpp:73` | `no member named 'replace' in namespace 'std'` | 补 `<algorithm>` |
| 5 | `bootable/recovery/volume_manager/include/volume_manager/VolumeManager.h:36` | `no template named 'vector' in namespace 'std'`，连带 `-Woverloaded-virtual` | 补 `<vector>` |

注意第 5 轮：同一个头文件缺失会**连带触发别的错误**。`VolumeManager.h` 缺 `<vector>` 时，
基类 `VolumeWatcher::handleEvent` 的签名解析失败，导致派生类 `VolumeClient::handleEvent`
被判定为「隐藏了重载的虚函数」而报 `-Werror,-Woverloaded-virtual`。
补上 `<vector>` 后两个错误一起消失——**修第一个报错，往往连带修掉后面几个**。

另外 `PublicVolume.cpp` 在 `bootable/recovery` 和 `system/vold` 各有一份，是不同副本，
两处都要补。

两处都是**上游代码的疏漏**，与 pandora 机型树无关。

### 工具

```bash
# 专用（带锚点断言）
python3 scripts/maintain/fix_recovery_algorithm.py [--revert]

# 通用：给任意源文件补标准头
python3 scripts/maintain/add_include.py <相对源码根的路径> <头1>[,<头2>] [--revert]

# 例
python3 scripts/maintain/add_include.py \
    vendor/qcom/opensource/vibrator/aidl/VibratorSelector/VibratorSelector.cpp \
    memory,vector
```

`add_include.py` 的行为：已包含则跳过（幂等）；插入到第一个 include 区块内最后一条
`#include <...>` 之后；插入行带 `// pandora-fix: missing std header` 标记，
`--revert` 按标记精确撤销。

### 经验

这类错误是**逐个暴露**的——每次修完一个，编译推进几十个百分点后再撞下一个。
好在 ninja 会跳过已完成的目标，每轮续编只重编失败点之后的增量，总耗时会收敛。

排查套路：

```bash
grep -A30 "<出错的 .o 路径>$" /root/d3.log | grep -E "error:|note:"
```

看到 `undefined template 'std::xxx'` 或 `no member named`，基本都是缺对应的标准头。

---

## 二十、预编译内核设备缺 IPA 内核头（`linux/msm_ipa.h`）

### 现象

```
hardware/qcom-caf/sm8850/dataipa/ipanat/inc/ipa_mem_descriptor.h:34:10:
fatal error: 'linux/msm_ipa.h' file not found
```

失败模块：`libipanat`（后续还会波及 `ipacm`）。

### 机制

`ipanat/Android.bp` 的 `header_libs` 里声明了 `qti_ipa_kernel_headers`，它定义在
`hardware/qcom-caf/common/Android.bp`，走 `generated_kernel_header_defaults`：

```
generated_kernel_header_defaults
  -> generated_kernel_includes
     -> make -C $(TARGET_KERNEL_SOURCE) headers_install
```

**这条路要求有内核源码。** 我们用预编译内核，`TARGET_KERNEL_SOURCE` 指向的
`device/xiaomi/pandora-kernel/kernel-headers` 根本不存在，导出目录为空，
于是 `<linux/msm_ipa.h>` 找不到。

### 一个容易误判的细节

`dataipa/drivers/platform/msm/Androidbp`（**注意文件名没有点**）里其实定义了正确的实现——
用 genrule `qti_generate_ipa_kernel_headers` 从 `include/uapi/linux/*.h` 生成头。
但 soong 只认 `Android.bp`，这个文件被完全忽略，所以那套逻辑从未生效。

想启用它也走不通：genrule 依赖 `unifdef`（`external/unifdef` 不在树里）和
`headers_install.sh`（树里没有对应模块）。

### 实际修复

项目自带的 UAPI 头可直接给用户态用——`msm_ipa.h` 里本来就有
`#ifndef __KERNEL__` 保护，不需要 unifdef 处理。

`scripts/maintain/fix_ipa_headers.py`：

1. 在 `dataipa/drivers/platform/msm/Android.bp` 新建 `qti_ipa_kernel_headers_dp`，
   `export_include_dirs: ["include/uapi"]`
2. 给 3 处 `header_libs` 追加该模块
   （`ipanat` 1 处、`ipacm` 2 处——后者含 `ipacm` 与 `aidl_fuzzer_ipacm`）

只动 sm8850 的 dataipa 项目，不影响 `hardware/qcom-caf/common`，其它平台不受牵连。

### 同类问题的判断方法

`fatal error: 'linux/xxx.h' file not found` 且该头确实存在于某个 `include/uapi` 目录下，
基本就是「header_libs 指向的模块在预编译内核配置下导出为空」。
查证方式：

```bash
# 头到底在不在树里
find . -name "msm_ipa.h" -not -path "./out/*"

# 声明的 header_libs 是怎么定义的
grep -rn -A10 'name: "qti_ipa_kernel_headers"' --include=Android.bp . | grep -v "^./out/"
```

### 踩坑：新增 Android.bp 模块后整包构建仍用旧分析图

第一次应用修复后直接 `m bacon` 续编，**错误照旧**。查证发现：

- 新 `Android.bp` 已进 `out/.module_paths/Android.bp.list`
- 但失败目标的编译命令里没有新模块的 `-I` 路径

原因是那轮构建的 soong 分析发生在文件创建前后，模块没进依赖图。

**验证方式：先单独编目标模块，再续整包。**

```bash
m libipanat -j8        # 1 分 38 秒，直接验证 include 是否生效
```

单模块编过之后再 `m bacon`，增量续编即可。这比「整包跑 30 分钟才发现没生效」省得多。

---

## 二十一、`repo sync` 不下载 LFS 对象（webview.apk 是 134 字节的指针）

### 现象

```
external/chromium-webview/prebuilt/arm64/webview.apk: error: failed opening zip: Invalid file.
error: Command '[... aapt2, 'dump', 'badging', '.../webview.apk']' returned non-zero exit status 1.
```

### 根因

`repo sync` **默认不拉取 Git LFS 对象**，工作区里只留指针文件：

```
$ ls -la external/chromium-webview/prebuilt/arm64/webview.apk
-rw-r--r-- 1 root root 134 ... webview.apk

$ cat webview.apk
version https://git-lfs.github.com/spec/v1
oid sha256:1d2f61832b2596b0046cb82cf3634609ea866098d097a83fac27c35272ac726a
size 260835655
```

134 字节的文本被当成 APK 喂给 aapt2，自然报 Invalid file。

### 结构上的坑

`external/chromium-webview/prebuilt/<arch>` 是**独立的 repo 项目**，不是子目录：

```
external/chromium-webview/prebuilt/arm64/.git
  -> ../../../../.repo/projects/external/chromium-webview/prebuilt/arm64.git
```

所以 `git -C external/chromium-webview` 会报 "not a git repository"，
必须进到 `prebuilt/<arch>` 里操作。每个 arch 各有一份 `.lfsconfig`，
指向 `https://review.lineageos.org/...` 的 LFS 端点。

### 修复

```bash
cd external/chromium-webview/prebuilt/arm64
git lfs install --local
git lfs pull
```

`git lfs pull` 之后文件变成真实大小（260,835,655 字节），`file` 识别为 APK。

全树共 4 个指针文件：

| 架构 | 实际大小 |
|---|---|
| arm64 | 260,835,655 B |
| arm | 98,126,751 B |
| x86_64 | 358,908,264 B |
| x86 | 157,109,134 B |

合计约 875 MB。**即使只编 arm64，也建议全部拉齐**——`chromium-webview` 模块会引用所有架构。

工具：`scripts/maintain/pull_lfs_objects.sh`（自动扫描所有含 `filter=lfs` 的项目并拉取，
`--check` 只报告不下载）。

### 教训

`repo sync` 成功 ≠ 文件完整。凡是 prebuilt 目录里的 apk/jar/zip/so，
体积异常小（几百字节）就要怀疑是 LFS 指针：

```bash
find . -size -1k \( -name "*.apk" -o -name "*.jar" -o -name "*.so" \) \
  -not -path "./out/*" | xargs head -c 100 2>/dev/null | grep -l "git-lfs"
```

---

## 二十二、blobs 的 prebuilt 盖住了 aidl_interface，导致缺 AIDL 头

### 现象

```
device/xiaomi/sm8850-common/alsd/alsd.cpp:8:10:
fatal error: 'aidl/vendor/xiaomi/sensor/citsensorservice/ICitSensorService.h' file not found
```

### 机制

树里有两个同名模块 `vendor.xiaomi.sensor.citsensorservice-V1-ndk`：

| 来源 | 类型 | 是否导出头 |
|---|---|---|
| `device/xiaomi/sm8850-common/interfaces/citsensors/Android.bp` 的 `aidl_interface` | 源码生成 | ✅ 导出 `aidl/...` 头 |
| `vendor/xiaomi/sm8850-common/Android.bp:23041` | `cc_prebuilt_library_shared` | ❌ 只打包 .so |

后者带 `prefer: true`，soong 因此选择 prebuilt（中间产物目录被改名为
`prebuilt_vendor.xiaomi...`），源码版被盖住，头文件也就没了。

### 修复

`scripts/maintain/fix_citsensor_prebuilt.py`：把该 prebuilt 的 `prefer` 改为 `false`，
让 `aidl_interface` 生成的模块生效。

验证（`m alsd`）：

```
//device/xiaomi/sm8850-common/interfaces/citsensors:vendor.xiaomi...-V1-ndk copy ....so
//device/xiaomi/sm8850-common/alsd:alsd link alsd
Install: out/target/product/pandora/vendor/bin/hw/alsd
```

模块来源变成 `device/xiaomi/.../interfaces/citsensors`，alsd 链接通过。

### 通用判断

`fatal error: 'aidl/...' file not found` 且该 AIDL 接口确实在设备树里定义时，
先查是否有同名 prebuilt 抢了优先级：

```bash
grep -rn 'name: ".*-V[0-9]*-ndk"' --include=Android.bp vendor/ | head
grep -rn -B2 -A20 'prefer: true' --include=Android.bp vendor/xiaomi/*/Android.bp | grep -A20 'ndk'
```

prebuilt 只提供二进制，不导出生成的头；源码版才带头。

### 副作用

改 `prefer` 会让 soong 全量重分析（本次 13 分钟）。改完先用 `m <module>` 验证，
不要直接跑整包。

---

## 二十三、头文件里的全局变量导致 `duplicate symbol`

### 现象

```
FAILED: .../wpa_supplicant/android_vendor_arm64_armv8-a-branchprot_cfi/unstripped/wpa_supplicant
ld.lld: error: duplicate symbol: drv
>>> defined in .../lib_driver_cmd_qcwcn.a(driver_cmd_nl80211.o)
>>> defined in .../lib_driver_cmd_qcwcn.a(driver_cmd_nl80211_oem_data.o)
ld.lld: error: duplicate symbol: bss
```

`hostapd` 同时失败，因为它链接同一个静态库。

### 根因

`hardware/qcom-caf/wlan/qcwcn/wpa_supplicant_8_lib/driver_cmd_nl80211_common.h`
第 57-58 行在**头文件里**写了不带 `extern` 的全局定义：

```c
struct wpa_driver_nl80211_data *drv;
struct i802_bss *bss;
```

这个头被 6 个 `.c` 包含，每个目标文件都产出一个强符号。
现代编译器默认 `-fno-common`（clang 11+），重复的暂定定义不再合并，直接报错。

这两行是遗留代码——所有实际使用处都在函数内声明了同名局部变量。

### 修复

`scripts/maintain/fix_qcwcn_common.py`：给 `lib_driver_cmd_qcwcn` 加 `-fcommon`，
恢复「暂定定义按 COMMON 符号合并」的旧语义。**不改源码，语义不变。**

验证：`m wpa_supplicant -j8` → 1214 步，1 分 24 秒，通过。

### 备选方案与取舍

| 方案 | 风险 |
|---|---|
| 加 `-fcommon`（已采用） | 最低，不改代码语义 |
| 把两行改成 `extern` | 若真有代码引用全局符号，会变成 undefined reference |
| 删掉两行 | 同上，且更隐蔽 |

### 通用判断

`ld.lld: error: duplicate symbol: X` 且 X 是普通变量名（`drv`/`bss`/`buf`），
且定义来自同一个 `.a` 的多个成员，基本就是「头文件里写了不带 extern 的变量定义」。
查证：

```bash
grep -rn "^\s*struct .*\*\(drv\|bss\);" --include=*.h <项目目录>
```

---

## 二十四、SELinux Treble 兼容性测试：新增 public type 未登记

### 现象

```
FAILED: .../treble_sepolicy_tests_202604
SELinux: The following public types were found added to the policy without an
entry into the compatibility mapping file(s) found in
private/compat/V.v/V.v[.ignore].cil, where V.v is the latest API level.

hal_touchfeature_xiaomi_default hal_touchfeature_xiaomi_default_exec
hal_touchfeature_xiaomi_service iso9660 qsguard udf usb_uvc_config_prop
vendor_afp_prop vendor_bt_prop ... xtra_control_prop
```

共 61 个类型，全部来自 vendor sepolicy（blobs 与设备树新增的策略）。

### 机制

`treble_sepolicy_tests` 会检查 vendor 策略是否**新增了 public type**。
Treble 要求 vendor 分区不能随意扩充 public type，否则系统升级时可能冲突。
新增的类型必须二选一处理：

1. 在 `private/compat/<ver>/<ver>.cil` 里映射到旧类型
2. 在 `private/compat/<ver>/<ver>.ignore.cil` 里登记为「无历史对应物，无需映射」

我们这些类型都是新引入的，选 2。

### 修复

设备树里已有 `sepolicy/private/compat/` 目录，含 30.0 / 31.0 / 32.0 / 33.0 /
34.0 / 202404 / 202504 七套文件，**缺 202604**。

`scripts/maintain/fix_sepolicy_compat.py` 生成
`private/compat/202604/202604.ignore.cil`：

```
(type new_objects)
(typeattribute new_objects)
(typeattributeset new_objects
  ( new_objects
    hal_touchfeature_xiaomi_default
    ...
    xtra_control_prop
  ))
```

验证：`m treble_sepolicy_tests_202604 -j8` → 生成成功。

### 注意

每次 Android 大版本升级（API level 变），都会多出一套新的 `<ver>` 目录要求。
报错信息里给出的两个 review 链接是官方示例，格式照抄即可。

`ignore.cil` 是**逐版本独立**的，不能只往旧版本文件里加——新版本的检查只读新版本目录。

---

## 二十五、`check_elf_file`：DT_NEEDED 与 shared_libs 不一致

### 现象

```
FAILED: .../libwfdcommonutils.so.check_elf_file
vendor/xiaomi/sm8850-common/proprietary/system_ext/lib64/libwfdcommonutils.so:
error: DT_NEEDED "libdng_sdk.so" is not specified in shared_libs.
```

### 来龙去脉（自己挖的坑）

早期为了解决 vendor 变体级联（见第十一节），把 `libwfdcommonutils` 的
`shared_libs` 里那条 `libdng_sdk` 注释掉了。当时 soong 分析确实通过了，
但 `check_elf_file` 会在编译后校验：prebuilt `.so` 的 `DT_NEEDED` 条目
必须在 `shared_libs` 里声明。删了声明，校验就不过。

**教训**：删依赖只是把错误从「soong 分析期」推迟到「ELF 校验期」，问题没解决。

### 修复

`scripts/maintain/fix_wfd_elfcheck.py`：给该模块加 `check_elf_files: false`。

```bp
cc_prebuilt_library_shared {
    name: "libwfdcommonutils",
    ...
    system_ext_specific: true,
    check_elf_files: false,
}
```

这个 blob 包里**已有 29 处** `check_elf_files: false`，说明这是既定做法：
对「依赖无法在 AOSP 侧提供」的 prebuilt，关掉 ELF 校验是标准处理。

验证：`m libwfdcommonutils -j8` → 通过。

### 遗留风险

`libdng_sdk.so` 在运行时确实不存在于镜像里。如果 `libwfdcommonutils.so`
真的在加载时解析该符号，WFD 功能会失效。这属于**运行时问题**，
构建期无法验证，需刷机后实测。

`check_elf_files: false` 只跳过构建期校验，不改变二进制内容。

---

## 二十六、D3 完成：完整 ROM 构建成功

### 结果

```
[100% 4951/4951] //frameworks/base/api:module-lib-api-stubs-docs-non-updatable check current API
ninja: 7m00.97s Build Succeeded: 4913 steps - 11.67/s
#### build completed successfully (08:20 (mm:ss)) ####
```

产物：

```
lineage-24.0-20261031-UNOFFICIAL-pandora.zip   1,188,353,697 字节（1.11 GB）
sha256 ed4c316b4d5ebd7a19db90df2504de8d02554999f7f137970d03d6fac7395ef8
```

副本已放 `D:/WSL/out/pandora/`，sha256 一致。

### 包内分区（payload.bin 格式，共 15 个）

| 分区 | 大小 |
|---|---|
| system | 1,054,814,208 |
| product | 1,747,648,512 |
| system_ext | 620,830,720 |
| vendor | 672,915,456 |
| vendor_dlkm | 129,163,264 |
| boot | 100,663,296 |
| vendor_boot | 100,663,296 |
| recovery | 104,857,600 |
| odm | 31,248,384 |
| system_dlkm | 29,614,080 |
| dtbo | 23,068,672 |
| init_boot | 8,388,608 |
| pvmfw | 1,048,576 |
| vbmeta / vbmeta_system | 8,192 |

LOS 24 的 `m bacon` 产出的是 payload 格式 OTA，不是分散的 img 文件，
所以用 `unzip -l` 看不到 `boot.img` 之类，属正常。验证分区完整性要用
`tools/payload_dump.py <zip> <outdir> --list`。

### 全程回顾：11 轮续编

| 轮次 | 失败原因 | 剩余目标 |
|---|---|---|
| 1 | `<algorithm>`（recovery） | 111,018 |
| 2 | `<memory>`/`<vector>`（振动器 HAL） | 70,069 |
| 3 | `linux/msm_ipa.h`（IPA） | 50,018 |
| 4 | IPA 分析图未更新 + `<algorithm>`（vold） | — |
| 5 | `<vector>`（VolumeManager.h） | — |
| 6 | `<functional>`（指纹 HAL）+ LFS 指针 | — |
| 7 | prebuilt 盖住 aidl_interface | — |
| 8 | 头文件定义全局变量（`-fno-common`） | 13,095 |
| 9 | SELinux 兼容性未登记 | 4,853 |
| 10 | `check_elf_file` DT_NEEDED 校验 | — |
| 11 | **成功** | 0 |

单轮最长 1h12m（第 1 轮），最短 1m34s（后续增量）。累计约 4 小时。

### 修复清单（全部脚本化，可 --revert）

| 脚本 | 解决的问题 |
|---|---|
| `fix_recovery_algorithm.py` | recovery 的 `PublicVolume.cpp` 缺 `<algorithm>` |
| `add_include.py` | 通用补标准头（vold / 振动器 / 指纹 / VolumeManager.h） |
| `fix_ipa_headers.py` | 预编译内核设备缺 `linux/msm_ipa.h` |
| `fix_citsensor_prebuilt.py` | prebuilt 盖住 aidl_interface |
| `fix_qcwcn_common.py` | 头文件定义全局变量导致 duplicate symbol |
| `fix_sepolicy_compat.py` | SELinux 202604 兼容性忽略清单 |
| `fix_wfd_elfcheck.py` | `check_elf_file` 的 DT_NEEDED 校验 |
| `patch_manifest_stub.py` | `.repo` 缺失时 manifest 降级 |
| `pull_lfs_objects.sh` | 拉取 Git LFS 对象 |

### 未验证的部分

- **刷机启动（D4）**：完全未验证。构建成功不等于能开机。
- **WFD 运行时**：`libwfdcommonutils.so` 依赖的 `libdng_sdk.so` 不在镜像里（见第二十五节）。
- **overlay 数值**：继承自 popsicle，需按 stock 核对。
- **触摸方向**：未加 idc，依赖驱动层处理，需实测。

---

## 二十七、从 A16 blobs 迁移到 A17 blobs

### 起因

设备刷入用 A16 blobs 构建的 LOS 后卡在开机动画，清 data 后仍然卡住。
排查发现：

```
system/build.prop   ro.build.version.sdk=37   release=17      ← 系统是 Android 17
vendor/build.prop   release_or_codename=Baklava               ← vendor 二进制来自 Android 16
```

LOS 24 本身是 **Android 17**（SDK 37），而我们用的 blobs 来自 OS3.0.318.0（Android 16，
Baklava）。A16 vendor HAL 配 A17 framework，是合理的怀疑方向。

### 新官包

`pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip`，8.5 GB，
**58 个分区**（含 xbl/abl/tz/modem 等固件，A16 包只有 15 个）。

分区规模对比：

| 分区 | A16 | A17 |
|---|---|---|
| odm | 31 MB | 3.6 GB |
| product | 1.7 GB | 4.4 GB |
| system | 1.05 GB | 932 MB |
| vendor | 673 MB | 562 MB |

`odm` 暴涨的原因是 A17 把相机 HAL、虹软算法库（`libarcsoft_*.so` 单个 230 MB）、
AI 模型（`.minn`/`.bin`）都放在了 odm。

### 两种提取策略与踩坑

**策略一：全量复制**（`rebuild_blobs_a17.sh`）——失败，踩了四个坑：

| 问题 | 数量 | 处理 |
|---|---|---|
| `qcril_config_database` 依赖未定义模块 | 2 | 补 SQL `filegroup` |
| 打包冲突（`libbinder.so`/`libc++.so`/`bin/awk`…） | 277 | 剔除 |
| 残留冲突（`etc/ueventd.rc` 等在多个分区都有） | 5 | 脚本改为删全部匹配 |
| 32 位模块不存在（64 位-only 构建） | 135 | 剔除 |
| `symbols/` 下 ninja 重复规则 | 150+ | 剔除 |

**核心问题**：A17 的 vendor 分区包含大量 **AOSP 自己会编译的库**。
A16 的 blob 清单是**手工精选**的（vendor 1477 个文件、odm 只有 136 个），
全量复制必然撞车。

**策略二：外科式更新**（`rebuild_blobs_a17_surgical.sh`）——采用

保持 A16 的文件选择范围，只把二进制换成 A17 版本：

```
vendor:     A17 1363 个, 沿用 A16 114 个
odm:        A17 128 个,  沿用 A16 8 个
system_ext: A17 104 个,  沿用 A16 5 个
product:    A17 11 个
system:     A17 4 个
合计 1737 个（A17: 1610, A16: 127），636 MB
```

A16 的选择是经过验证能编译的，沿用它能避开所有「新增 blob 与 AOSP 模块撞车」的问题。

### 关键教训

1. **全量复制 stock 分区当 blob 包是错的**。stock 分区里包含 AOSP 自编译的组件，
   LineageOS 的 blob 清单必须精选。
2. **A17 的 `system.img` 是嵌套布局**：镜像根是 `/`，真正的 system 内容在
   `<mount>/system/` 下。`vendor`/`odm`/`system_ext`/`product` 则是平铺。
3. **WSL 空闲关闭会丢 loop 挂载**。所有挂载 + 提取必须在同一个 WSL 会话内完成。
4. ninja 的规则可能被换行拆开（`build $\n  out/...`），用行首锚点做扫描会漏。

### 工具

| 脚本 | 用途 |
|---|---|
| `scripts/device/rebuild_blobs_a17.sh` | 全量提取（含 odm 相机排除） |
| `scripts/device/rebuild_blobs_a17_surgical.sh` | 按 A16 清单更新二进制 |
| `scripts/maintain/fix_rildb_filegroups.py` | 补 qcril SQL filegroup |
| `scripts/maintain/drop_conflicting_blobs.py` | 按打包冲突剔除 |
| `scripts/maintain/drop_modules_by_name.py` | 按模块名剔除 |
| `scripts/maintain/drop_paths.py` | 按相对路径剔除 |
| `scripts/flash/backup_partitions.sh` | 备份关键分区到 PC |
| `scripts/flash/flash_fastbootd.sh` | fastbootd 批量刷入 |

---

## 二十八、替换内核：A16 GKI → A17 GKI

### 发现

排查卡开机时忽略了内核。实际检查构建产物：

```
Linux version 6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k
```

内核是 **A16 GKI**（`android16-5`），而 system 是 Android 17（SDK 37）。
这比 vendor HAL 不匹配更可能是卡开机的原因。

A17 官包（OS4.0.5.0）的内核：

```
Linux version 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
```

版本跨度 6.12.23 → 6.12.69，GKI 分支 `android16-5` → `android16-6`。
GKI 分支名仍带 android16（6.12 LTS 的分支命名），但这是 A17 实际出货的内核。

### 内核必须整体替换

KMI 要求内核与模块严格匹配，所以 kernel / vendor_dlkm / system_dlkm /
vendor_ramdisk 的模块必须一起换。

### 做法

`scripts/build/make_pandora_kernel_a17.sh`，流程与 A16 版一致：

1. `payload_dump.py` 提取 boot / vendor_boot / dtbo / vendor_dlkm / system_dlkm
2. `unpack_bootimg.py` 解出内核与 vendor_boot 的 dtb / vendor_ramdisk
3. vendor_ramdisk：`lz4 -d` + `cpio` 解包
4. vendor_dlkm / system_dlkm：EROFS，用 `fsck.erofs --extract`
5. `split_dtb.py` 拆分 dtb 并校验拼接还原一致
6. 组装到 `device/xiaomi/pandora-kernel`

结果：

| 项 | A16 | A17 |
|---|---|---|
| kernel | 39,963,136 | 41,511,424 |
| dtbo.img | 23,068,672 | 23,068,672 |
| dtb 文件 | 8 | 12 |
| vendor_ramdisk .ko | 416 | 461 |
| vendor_dlkm .ko | 374 | 402 |
| system_dlkm .ko | 103 | 103 |

### 隔离变量

为单独验证「内核版本」这一个假设，**恢复了 A16 blob 包**
（`/root/backup-sm8850-a16`，620 MB），只改内核。

构建通过，产物 `lineage-24.0-20261101-UNOFFICIAL-pandora.zip`（1,189,616,135 字节），
包内 boot.img 内核经解包验证为 `6.12.69-android16-6`。

### 备份

原 A16 内核目录备份在 `/root/backup-pandora-kernel-a16`（262 MB）。

---

## 二十九、vendor_dlkm / system_dlkm 是逻辑分区，必须用 fastbootd

### 现象

在 bootloader 模式（`is-userspace: no`）下刷内核相关分区：

```
[1/5] boot         OK
[2/5] dtbo         OK
[3/5] vendor_boot  OK
[4/5] vendor_dlkm  FAILED (remote: '(vendor_dlkm_a) No such partition.')
```

### 原因

`vendor_dlkm` 和 `system_dlkm` 在这台机器上是 **super 内的逻辑分区**，
bootloader 模式的 fastboot 只认物理分区表，看不到它们。
必须先进 fastbootd（`is-userspace: yes`）才能刷。

### 后果

刷了 `boot`（A17 内核 6.12.69）但 `vendor_dlkm` 没刷进去，
设备变成 **A17 内核 + A16 模块**，KMI 不匹配，模块无法加载，
卡在小米开机第一屏，TWRP 也进不去。

### 正确顺序

```
1. fastboot flash boot / dtbo / vendor_boot     ← bootloader 模式可以
2. fastboot reboot fastboot                     ← 进 fastbootd
3. fastboot flash vendor_dlkm / system_dlkm     ← 逻辑分区必须在这里刷
4. fastboot reboot
```

### 教训

内核替换必须**整体原子完成**：kernel + vendor_dlkm + system_dlkm + vendor_boot
四个部分任一遗漏都会导致 KMI 不匹配而无法启动。
刷之前应确认目标分区是物理还是逻辑，避免刷到一半中断。

---

## 三十、只刷物理分区会导致系统与 recovery 双双无法启动

### 事故经过

设备线刷 OS4.0.5.0（A17 原厂）后，按「阶段 1 物理分区 + 阶段 2 逻辑分区」的方式刷 LOS：

```
阶段 1（bootloader 模式，已执行）：
  boot init_boot dtbo vendor_boot vbmeta vbmeta_system   ← 全部替换为 LOS 版本

阶段 2（fastbootd，未执行）：
  system system_ext product vendor odm vendor_dlkm system_dlkm
```

结果：系统进不去，recovery 也进不去，只能进 fastboot。

### 根因

两个独立原因叠加：

1. **AVB 校验链断裂**
   `vbmeta` / `vbmeta_system` 被替换为 LOS 签名版本，而 system/vendor/odm
   仍是小米密钥签名的原厂镜像。AVB 用新 vbmeta 校验旧分区 → 失败 → 拒绝启动。

2. **ramdisk 与系统不匹配**
   `boot` / `init_boot` / `vendor_boot` 是 LOS 版本，ramdisk 期望 LOS 的 system，
   而 system 还是原厂。

recovery 同样受 vbmeta 影响——它也要过 AVB 校验。

### 恢复

只刷了 6 个物理分区，system/vendor/odm **从未被触碰**，仍是原厂。
所以只需从官包恢复那 6 个：

```bash
# 从 OS4.0.5.0 完整包提取
payload_dump.py pandora-ota_full-OS4.0.5.0...zip <out> \
    boot init_boot dtbo vendor_boot vbmeta vbmeta_system

# bootloader 模式刷回（vbmeta 放最后）
fastboot flash boot / init_boot / dtbo / vendor_boot / vbmeta_system / vbmeta
fastboot reboot
```

恢复后验证：

```
ro.build.fingerprint  Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM:user/release-keys
uname -r              6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
ro.boot.verifiedbootstate  orange
```

系统正常启动，TWRP 3.7.1 也能进。

### 正确做法

**不要分两阶段刷**。这台机器的 `fastboot reboot fastboot` 从 bootloader
进不了 fastbootd（实测只重启回 bootloader），正确路径是：

```
1. 设备在可启动的原厂系统里
2. adb reboot fastboot          → fastbootd（is-userspace: yes）
3. fastboot flash <全部 13 个分区>   ← fastbootd 既能刷逻辑分区也能刷物理分区
4. fastboot reboot
```

关键点：**vbmeta 必须与 system/vendor/odm 一起刷**，不能只刷一半。
要么全刷 LOS，要么全留原厂。

### 遗留

当前设备：原厂 A17 系统 + 原厂 A17 内核 + TWRP 3.7.1 recovery，可正常使用。
LOS 的 13 个分区镜像已备好在 `D:/WSL/out/pandora/los1101/`（4.31 GB）。
