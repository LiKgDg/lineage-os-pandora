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
