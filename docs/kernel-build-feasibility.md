# pandora 内核源码编译可行性报告

> 结论先行：**当前 LOS24 树是「预编译内核」架构，源码编译内核投入产出不划算。**
> 定位 D4 启动失败的正确路径不是自编内核，而是「查 pstore 为什么空」——纯取证，不碰内核。

---

## 一、结论

| 问题 | 结论 |
|---|---|
| 小米官方是否放出 SM8850 内核源码 | **否**（`MiCode/Xiaomi_Kernel_OpenSource` 267 个分支，最新到 w 代，无 SM8850） |
| 内核源码唯一来源 | 第三方 `LokumKernel-SM8850/android_kernel_xiaomi_sm8850`（真 ACK 源码，Linux 6.12.23） |
| 该来源是否干净 | **否**，main 分支已焊入 KernelSU + SUSFS；干净基线在 commit `6edeb476` |
| 小米 SM8850 内核定制量 | **仅一行 `CONFIG_RFKILL=y`**，其余走 GKI `gki_defconfig` |
| 源码编译内核可行吗 | 可行，但要装配 Kleaf 完整 toolchain，**数天量级** |
| 值得做吗 | **除非长期维护 pandora 内核，否则不值得** |

## 二、为什么源码编译成本这么高（三层调查）

连续三层调查，每层都推翻上一层的乐观判断：

### 第 1 层：以为补 `build/kernel`（kleaf）就行

内核仓 `BUILD.bazel` 顶部 `load("//build/kernel/kleaf:...")`，第一反应是"补个 kleaf 目录就能编"。

**查证**：`build/soong/kernel/` 里**没有调 kleaf 的代码**，全部是
`prebuilt_kernel_modules.go` + `kernel_modules_builder/` —— 这是**处理预编译模块打包**的
（soong_zip / depmod / llvm-strip），不是源码编译。

### 第 2 层：以为 soong 内核桥接完整

看到 `build/soong/kernel/kernel_modules_builder/` 存在，以为内核编译桥接是齐的。

**查证**：那套东西只管**预编译模块**，不碰内核源码。soong 里没有任何
「调 bazel 编内核 Image」的代码（grep `kleaf|bazel build` 零命中）。

### 第 3 层：以为 A2（独立 bazel）只需写 WORKSPACE

内核仓自带 `BUILD.bazel`，`xiaomi_sm8850_kernel_aarch64` target 都配好了，
以为补个 WORKSPACE + 标准依赖就能编。

**查证**：kleaf（`kernel/build` 仓）依赖一整套 toolchain：
`@kleaf_clang_toolchain`、`@gki_prebuilts`、`@dtc`、`@dwarves`、`@kmod`、
`@pigz`、`@kleaf_rust_toolchain`…… 这些由 AOSP 根 WORKSPACE 统一定义，
独立装配要拉几个 GB prebuilt，且版本要和 soong/bazel 严格对齐。

### 根因

这套 LOS24 树的 `BoardConfig.mk` 里有：

```make
TARGET_NO_KERNEL_OVERRIDE := true
```

这**不是权宜之计**，是这套树唯一支持的模式——它从搭建时就选择了「预编译内核」，
压根没装「源码编译内核」这条链（soong → kleaf → bazel）。

## 三、已落地资产

| 资产 | 位置 | 说明 |
|---|---|---|
| 内核干净基线源码 | `/root/los24/kernel/xiaomi/sm8850` | Linux 6.12.23，已去 KSU/SUSFS，62 symlink 完整 |
| kleaf 源码 | `/root/work/kleaf` | `kernel/build` 仓，5.2 MB |
| 干净基线 commit | `6edeb476` | `ANDROID: import Xiaomi SM8850 stock GKI baseline`，孤儿 commit |

> 这些资产已保存，若将来决定长期维护 pandora 内核，可以此为基础继续。

## 四、对取证有硬价值的几个结论

### 4.1 `console=ttynull` 是内核内建的，改设备树改不掉

```
strings device/xiaomi/pandora-kernel/kernel | grep console=
→ console=ttynull
```

它是 `CONFIG_CMDLINE="console=ttynull"` 编译进内核的，不在任何 `.mk` / dts 里。
**之前"改 BoardConfig 去掉 console=ttynull"的建议是错的，已撤销。**

### 4.2 vendor cmdline 能追加（已实测）

`BOARD_KERNEL_CMDLINE` 实际写进 `vendor_boot` 的 vendor cmdline（`boot.img` 的 cmdline 是空的）。
追加 `sysctl.kernel.hung_task_panic=1` 那次，解包验证过参数确实进了 vendor_boot 并被内核消费。

### 4.3 Linux console 覆盖规则

后出现的 `console=` 覆盖前面的。内建 `console=ttynull` 在前，vendor cmdline 在后，
理论上追加一个真实 console 设备就能覆盖。
**但 pandora 无物理串口**（除非拆机引 UART），`console=ttyS0` 无意义。

### 4.4 真正该查的：pstore 为什么空

设备 dmesg 白纸黑字：

```
printk: legacy console [ramoops-1] enabled
pstore: Registered ramoops as persistent store backend
ramoops: using 0x200000@0xff400000
```

ramoops console **已经 enabled**，pstore 后端也注册了，但 `/sys/fs/pstore` 是空的。
这个矛盾**还没定位**，而且它比"改 console"更有价值——因为它是纯取证，不碰内核。

可疑方向（待验证）：`mtdoops` 与 `ramoops` 注册在**同一块 2 MB 区域**
（都指向 `0xff400000`），先注册者占用，可能 mtdoops 把区域占了导致 ramoops 写不进。

## 五、建议的下一步（按投入产出排序）

1. **查 pstore 为什么空** —— 纯取证，设备上电即可做，不碰内核、不刷机
2. **B 路线：vendor cmdline 追加 console 覆盖** —— 需先确认 pandora 有无可用 console 设备
3. **A1/A2 完整内核编译** —— 数天量级，仅当决定长期维护 pandora 内核

## 六、教训

连续三次"重估成本都上调"，根因是**每层只查一层就下结论**：

```
第1次：「补 build/kernel 就行」→ 查一层 → 推翻
第2次：「soong 桥接完整」→ 查一层 → 推翻
第3次：「A2 只需写 WORKSPACE」→ 查一层 → 推翻
```

> 对涉及多组件协作的构建链路（soong → kleaf → bazel → toolchain），
> 必须在给工作量估计前，把**整条链每一环**都查清楚，而不是查到第一个阻塞就下结论。

---

## 附：关键命令备忘

```bash
# 绕过坏代理下载内核源码（git/curl 走 55637/56813 已 502，只有 gh api 通）
gh api "repos/LokumKernel-SM8850/android_kernel_xiaomi_sm8850/tarball/6edeb476" > clean.tar.gz

# 拉 kleaf 源码（代理 7890 对 git 通了）
git -c http.proxy=http://127.0.0.1:7890 clone --depth 1 \
    https://android.googlesource.com/kernel/build kleaf

# 验证预编译内核内建的 console
strings device/xiaomi/pandora-kernel/kernel | grep -oE "console=[^ ]*"

# 提取 oops 分区日志（设备在 recovery 时）
bash scripts/maintain/extract_crash_logs.sh

# 追加 vendor cmdline 诊断参数（--check/--apply/--revert）
bash scripts/maintain/patch_cmdline_diag.sh --check
```
