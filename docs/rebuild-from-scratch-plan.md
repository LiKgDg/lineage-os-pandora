# pandora LOS24 从零重建方案（方案 A：仓库化 + 自编内核）

> 目标：让这台小米 17 Pro（pandora / SM8850）的 LineageOS 24.0 移植能**从零复现**，
> 并且解决「刷进去起不来、又拿不到日志」的死局。

## 为什么是 A，不是「直接重编」

实测（见 `docs/los24-build-notes.md` 第 35、36 节）：

1. 当前配置**能编包**（`m nothing` 绿），但**刷进去起不来**——normal boot 卡住、USB 不枚举、
   设备自动回落 recovery。
2. 拿不到日志：`/sys/fs/pstore` 空（`console=ttynull`）、oops 分区只有 recovery 记录、
   失败那次没崩溃（挂住，`hung_task_panic` 也测了，不触发）。
3. 根因之一：**一直在用预编译内核**，改不了 `console`，所以永远看不到启动输出。

「从零重编」只是把同样的配置再跑一遍，**不会改变起不来的结果**。真正的瓶颈是缺日志，
而缺日志的根因是「改不了内核」。所以先自编内核，拿到日志，再谈配置和设备树怎么改。

## 现状盘点（已核实）

| 项 | 状态 |
|---|---|
| LOS24 源码树 | 234 GB，`/root/los24`，整体上传不可行 |
| 设备树 | `device/xiaomi/sm8850-common`(1.8M) + `pandora`(196K)，已拆三仓发布 |
| vendor blobs | 620 MB，本地有，未入库（超 GitHub 100 MB 限制） |
| 内核源码 | 本地无；唯一来源 `LokumKernel-SM8850/android_kernel_xiaomi_sm8850` |
| 小米官方内核 | **未放出 SM8850**（267 分支，最新到 w 代） |
| 预编译内核 | 41.5 MB，`device/xiaomi/pandora-kernel/kernel`，**无 IKCONFIG**（提取不到 config） |

## 四步路线

### 第一步：内核源码接入 + 自编带日志的内核

1. 克隆 `android_kernel_xiaomi_sm8850` 到 LOS 标准路径 `kernel/xiaomi/sm8850`
2. 写 `build.config.pandora`：基于 GKI defconfig，**开 `CONFIG_CMDLINE` console** 与
   `CONFIG_ANDROID_RAM_CONSOLE`（pstore），关掉 `console=ttynull`
3. 用 LOS 内置 clang（`prebuilts/clang/host/linux-x86/clang-r596125`）编译
4. 产出 `boot.img` 或替换 `pandora-kernel/kernel`，单独刷 boot 验证

**这一步的验收标准**：刷入后 normal boot 卡住时，`/sys/fs/pstore` 有内容，或串口有输出。

### 第二步：一键复现

- `local_manifest.xml`：把 device/vendor/kernel 三个仓声明进 repo
- `sync.sh` + `build.sh`：一条命令重建整棵树 + 出整包

### 第三步：vendor blobs 入库

- 620 MB 走 GitHub Release（不用 LFS，避免 1GB 配额）
- manifest 里指到 Release 资产，`extract` 脚本自动解

### 第四步：基于日志重建设备树与配置

拿到第一步的失败日志后，定位卡在哪个 init 服务 / 哪个 wait_for，再有依据地改
`BoardConfig.mk`、`init.*.rc`、`fstab`。

## 关键风险

| 风险 | 应对 |
|---|---|
| 第三方内核仓基线不纯（加了 SUSFS/KSU） | 用它的 stock GKI 基线 commit，不用 SUSFS 分支 |
| 自编内核与预编译 `.ko` 的 module_layout 不匹配 | 第一步只验证启动，不加载 vendor 模块；日志优先 |
| 设备没电/离线 | 先做纯文件工作，刷机前再上电 |
| 无 config（IKCONFIG 缺失） | 用 GKI `gki_defconfig` + 小米 device 树里的 dts 推断，不追求与预编译一致 |

## 提交与仓库规划

| 仓库 | 内容 | 说明 |
|---|---|---|
| `lineage-os-pandora`（已有） | 全部工具/脚本/文档/设备树 | 继续做总仓 |
| `android_device_xiaomi_sm8850-common`（已有） | 通用设备配置 | 已发布 |
| `android_device_xiaomi_pandora`（已有） | 机型树 | 已发布 |
| `android_device_xiaomi_pandora-kernel`（已有） | 内核清单/校验 | 已发布 |
| `android_kernel_xiaomi_sm8850`（新增） | 内核源码 fork | 从 LokumKernel fork，去 SUSFS |

## 进度记录（2026-11-03 05:xx）

### 已完成：内核源码接入（第一步的前半）

- 网络：git/curl 走 `127.0.0.1:55637` 代理已 502，只有 `gh api` 能通
  （走 58800 MCP 通道）。用 `gh api .../tarball/main` 下载内核源码 tarball 239 MB 成功。
- 解压到 WSL ext4（`/root/kernel-src/sm8850-kernel`），1.7 GB，63 个 symlink 完整。
  **教训**：PortableGit 的 `/root/work` 不是 WSL 的 `/root/work`，前者映射到
  `C:/Users/MSI/AppData/Local/Programs/WorkBuddy/resources/vendor/PortableGit/root/work`。
- 内核版本 **Linux 6.12.23**，与预编译内核 `6.12.23-android16-5` 同代，对得上。

### 关键发现：源码不是「干净的小米基线」

`arch/arm64/configs/xiaomi_sm8850_bootimg.fragment` 实际是 LokumKernel 作者改造过的：

```
CONFIG_LOCALVERSION="-android16-5-LokumKernel"
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y  (SUSFS 全家桶)
```

即：**KernelSU + SUSFS 已焊进内核**，fragment 不是小米原版。小米官方
`MiCode/Xiaomi_Kernel_OpenSource` 尚未放出 SM8850 分支（267 分支，最新到 w 代）。

### 下一步（待做）

1. 从 LokumKernel 提交历史定位「小米 SM8850 stock GKI baseline」那个原始 import commit，
   切回干净基线（去掉 KSU/SUSFS），这是自编内核的正确起点。
2. 在干净基线上，写自己的 `build.config.pandora`：GKI defconfig + 小米 fragment，
   **开 `CONFIG_ANDROID_RAM_CONSOLE` + 去掉 `console=ttynull`**（日志的目标）。
3. 用 LOS 内置 clang 编译，产出 boot.img。
4. fork 到 `LiKgDg/android_kernel_xiaomi_sm8850`。
