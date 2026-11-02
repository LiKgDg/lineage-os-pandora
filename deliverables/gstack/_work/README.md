# 离线取证工作区

本目录是 `../offline-evidence-closure-los24-kmi-2026-11-01.md` 的取证工作区。全部只读分析，未修改 `docs/`、`device-trees/`。

**分两条线**（依据报告 §5.4 的裁定）：

| | 放哪 | 内容 |
|---|---|---|
| 中间态 | WSL 的 `/root/work/gstack/`（`$STAGE`） | 解包树、`.ko` 集合、`mount` 点、`stock_*.img`、`*.cpio` |
| 证据 | 本目录（Windows，随报告交付） | fstab 文本、内核配置、哈希与 CRC 报表、脚本 |

> 不放 `/tmp`（WSL 空闲重启会清空），不放 `/mnt/c` 存 `.ko`（9p 慢、缺可执行位、旧世代模块会在共享目录里存活）。

---

## 一、一键准备

```bash
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-stage-init.sh"
```

从 stock OTA 提取 `vendor_boot` / `vendor_dlkm` / `system_dlkm` 到 `$STAGE`，解两侧 ramdisk 到 `$STAGE/vb/{los,stock}`。
实测约 1 分钟，产出 373 MB。**`vendor`（589 MB）默认不提取**，需要时加 `--with-vendor` 或设 `WANT_VENDOR=1`。

其它脚本都会 `source wsl-common.sh` 并自动调用 `ensure_ramdisks`，**单独跑任何一个都不会出现「静默 0 行」**（缺 stage 会报 `FATAL` 并 exit 9）。

---

## 二、证据文件（本目录，体积小）

| 文件 | 内容 |
|---|---|
| `fstab-qcom-los.txt` | LOS `vendor/etc/fstab.qcom`（8,928 B，sha256 `6a6f28e5…`） |
| `fstab-qcom-stock.txt` | stock `vendor/etc/fstab.qcom`（13,814 B，sha256 `391d5143…`） |
| `los_vendor_etc_fstab.qcom` / `los_first_stage_fstab.qcom` | LOS 两份副本，逐字节相同 |
| `stock_first_stage_fstab.qcom` | stock 的 first-stage 副本，与 `fstab-qcom-stock.txt` 同内容 |
| `los_kconfig.txt` | LOS 内核配置（223,592 B），含 `CONFIG_PSTORE_RAM=y`、`CONFIG_ANDROID_BINDER_IPC=y` |
| `gate-test.log` | 门禁脚本自测日志 |

**结论**：两侧 userdata 行 flags 逐项相同（都含 `formattable`），唯一差异是 LOS 多 `,atgc`；`/metadata` 两侧都是 f2fs。

---

## 三、脚本

### WSL（真实工具，需 root）

| 脚本 | 用途 |
|---|---|
| `wsl-common.sh` | 公共前置：`STAGE`/`WORK`/`IMGS` 路径、`need()` 断言、`ensure_ramdisks`、`ensure_stock_dlkm_mount`、`crc_of` |
| `wsl-stage-init.sh` | 一次性构建 stage（幂等） |
| `wsl-fstab4.sh` | 四来源 fstab 比对 + sha256 + flags 差集 |
| `wsl-modinfo.sh` | `modinfo -F vermagic` 统计两侧分布 |
| `wsl-crc.sh` | `modprobe --dump-modversions` 取 `module_layout` CRC，带 PASS/FAIL 判定 |
| `wsl-cover-vb.sh` | vendor_boot 错配模块的可替换率 + `modules.load` 悬空项 |
| `wsl-cover.sh` / `wsl-dlkm.sh` / `wsl-setdiff.sh` / `wsl-gap.sh` | vendor_dlkm 侧的同口径核对 |
| `kmi-gate.sh` | **已迁出** → `scripts/maintain/kmi-gate.sh`（构建期门禁，属于仓库工具而非取证证据） |

### PixelOS 交叉验证（2026-11-02 新增）

产物在 WSL `/root/work/pixelos/`（约 300 MB），源在 `PixelOS_pandora-17.0-20261102/`。

| 脚本 | 用途 |
|---|---|
| `wsl-pixelos.sh` | 解 `vendor_boot` / `vendor_dlkm` / `system_dlkm`，统计三处模块的 vermagic 与 CRC |
| `wsl-pixelos-cmp.sh` | vendor_boot 的字节关系（PixelOS vs stock vs LOS）+ 悬空项归属 + 清单对账 |
| `wsl-pixelos-dlkm.sh` | 两个 dlkm 分区的字节关系 |
| `wsl-pixelos-load.sh` / `wsl-pixelos-vbload.sh` | 两侧 `modules.load` 的条目级差集 |
| `wsl-pixelos-atomic.sh` | **原子执行**：挂载 → 四份 system_dlkm 清单对账 → 门禁对 PixelOS / LOS 的判定 |
| `wsl-pixelos-fstab.sh` | fstab 与 cmdline 对照 |
| `wsl-pixelos-nonko.sh` | ramdisk 非模块文件比对（结论：468 文件里只错 410 个） |
| `wsl-pixelos-stockeq.sh` | 确认 stock 与 PixelOS 的索引文件同源 |
| `wsl-pixelos-light.sh` | dtb 段哈希 + init_boot ramdisk 探测 |
| `wsl-pixelos-init.sh` | init_boot 完整比对（**超时未跑完**，见交叉验证报告 §11.2） |

```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-pixelos-atomic.sh"
```

> **loop 挂载不跨 WSL 重启**（`/root` 下的文件持久，但 `mount` 不持久）。所以凡是要挂载的脚本都写成「挂载 + 分析」一次跑完，不要分两次调用。

### 实机取证（2026-11-02，设备在环）

设备：pandora / 25098PN5AC，已刷 PixelOS，`adb` + KernelSU `su` 可用。
**Git Bash 调 adb 也必须加 `MSYS_NO_PATHCONV=1`**，否则 `/data/local/tmp/...` 会被改写成 Windows 路径。

| 脚本 | 用途 |
|---|---|
| `device-grab.sh` | 一次采全：身份、cmdline、`/proc/modules`、三处分区清单、`modules.load`、fstab、`dmesg`、pstore、`getprop`、挂载表 |
| `device-vendor-id.sh` | 确认运行中的 `/vendor` 是哪一份：`ro.vendor.build.*`、挂载来源、索引文件 md5、模块数 |
| `device-sample.sh` | 抽样 40 个 `.ko` 做 md5（来源校验用） |
| `wsl-provenance.sh` | 设备抽样哈希 vs 镜像同名文件（结论：40/40 相同） |
| `wsl-dev-cmp.sh` / `wsl-dev-cmp2.sh` | 实机 `lsmod` vs 三份清单的加载率 |
| `wsl-dev-miss.sh` | **量化 LOS 会漏加载多少个模块**（结论：41 个） |

设备侧产物在 `/data/local/tmp/out{,2,3}`，拉回本地后在 `device-pixelos/`：

| 目录 | 内容 |
|---|---|
| `device-pixelos/dump/` | 18 个文件：`lsmod.txt`、`proc-modules.txt`（666 行）、`dmesg.txt`（5,645 行）、`fstab.qcom`、`getprop-all.txt`、`pstore.txt` 等 || `device-pixelos/out2/` | vendor 身份、索引 md5、modprobe 实测 |
| `device-pixelos/out3/` | 40 个抽样 `.ko` 的 md5 |
| `device-pixelos/pmsg-ramoops-0.txt` | pstore 里唯一的文件（1,785 B，内容是 modem AT 流，**不是内核日志**） |

**关键结论**：`sys.boot_completed=1`；索引 md5 与镜像逐字节相同；抽样 40/40 相同；fstab sha256 = `6a6f28e52f57…`（与 LOS 相同）；`panic_on_oops=1`、`hung_task_panic=0`。

**注意 `dmesg` 的环形缓冲会回卷**：本次采集时最早一行只到 `[106.238387]`，`[0.000000]` 起的启动日志已丢失。要拿完整启动日志必须在重启后立刻抓。

> **踩坑**：本地目录原本叫 `out/`，被 `.gitignore` 里的 `out/` 规则整目录吞掉（git 无法对被排除的目录再做反包含）。已改名为 `dump/`。以后放取证产物不要用 `out/`、`extracted/`、`archives/` 这些名字。

```bash
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-crc.sh"
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "$W/wsl-cover-vb.sh"
```

### Python（手写只读解析器，Windows 可直接跑，只吐文本）

`ext4mini.py` / `erofsmini.py` / `cpiomini.py` / `lz4legacy.py` / `payload.py` / `bootimg.py` / `fdtmini.py`
`extract_fstab.py` / `compare_fstab.py` / `check_kmi.py` / `kmi_scan.py` / `wsl_extract_part.py`（payload 分区提取）

---

## 四、踩过的坑（复跑前先看）

1. **Git Bash 调 `wsl.exe` 必须加 `MSYS_NO_PATHCONV=1`**，否则 `/mnt/c/...` 会被改写成 `C:/...`。
2. **`$VAR` 会被外层 shell 提前展开**，所以脚本要写成文件再 `wsl bash <path>`，不要拼 `bash -c '...'`。
3. **WSL 空闲会重启，`/tmp` 不保留**——这就是所有中间态都要放 `$STAGE` 的原因。
4. **`dump.erofs` 版本太老**，没有 `--cat`；读单个文件用 `mount -t erofs`。

---

## 五、关键数值（真实工具复核，与手写解析器一致）

```
LOS vendor_boot  461 个 .ko : 405 × 0xe976b219 (6.12.23/android16-5) + 56 × 0x797f2b3e
stock vendor_boot 461 个 .ko : 461 × 0x797f2b3e (6.12.69/android16-6)
LOS vendor_dlkm  402 个 .ko : 366 × 0xe976b219 + 36 × 0x797f2b3e
stock vendor_dlkm 402 个 .ko : 402 × 0x797f2b3e
LOS system_dlkm  版本化目录 103 全对 / flatten 副本 102 错
内核             6.12.69-android16-6-g43b5ab7e247d  (期望 CRC = 0x797f2b3e)

modules.load 150 条 → 142 CRC 不符 + 8 条文件缺失 = 可加载 0 条
修复覆盖率：vendor_boot 405/405、vendor_dlkm 366/366（100%，零缺口）
两侧 vendor_dlkm 模块名集合完全相同（402 vs 402，零差异）——替换不引入新文件
```

## 六、PixelOS 交叉验证的关键数值（2026-11-02）

```
PixelOS 内核      41,511,424 B，banner 与 LOS 逐字一致（6.12.69-…-abogki561813157-4k）
PixelOS 模块      461 / 402 / 103 / 103 全部 6.12.69 + 0x797f2b3e
PixelOS vs stock  vendor_boot 461/461、vendor_dlkm 402/402 逐字节相同；5 个索引 md5 全同
PixelOS vs LOS    vendor_boot 56 同 / 405 不同；vendor_dlkm 36 同 / 366 不同
                  system_dlkm 版本化 103/103 相同；flatten 1 同 / 102 不同
ramdisk 结构      468 vs 468 文件，名单完全相同；差异仅 405 .ko + 5 索引
                  fstab.qcom 与 modules.load.recovery 逐字节相同（sha256 6a6f28e52f57）
LOS 清单缺陷      幽灵 8+8 条；缺失本机模块 20（vb）+ 30（vd）= 50 个
门禁判定          PixelOS 三集合 PASS / exit 0；LOS 三集合 FAIL / exit 1
```
