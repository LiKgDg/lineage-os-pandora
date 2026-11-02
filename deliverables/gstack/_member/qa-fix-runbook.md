# 修复执行手册 —— INC-PANDORA-LOS24-001

**对象**：小米 17 Pro（pandora / SM8850）· LineageOS 24 · 内核模块 KMI 世代错配
**根因与证据**：`../offline-evidence-closure-los24-kmi-2026-11-01.md`（本手册不复述原理）
**数据来源**：本手册所有数字均为本轮实测（WSL Ubuntu 24.04 / kmod 31 / `modprobe --dump-modversions`），复跑入口见 §7
**符号约定**：`$K` = `$(KERNEL_PATH)` = `device/xiaomi/pandora-kernel`（BoardConfig.mk:8）。本轮该目录不在本工作区，命令按构建机路径写

> ## ⚠️ 2026-11-02 补遗：方案选型已翻转（A1 → A2+），本节之后凡推荐 A1 处一律以本补遗为准
>
> 拿到同机型 PixelOS 出货构建（`PixelOS_pandora-17.0-20261102/`）并在**实机**（已刷该包、adb + KernelSU 可用）上验证后，**本手册 §1 推荐 A1 的两条理由全部失效**：
>
> | 原理由 | 实测 |
> |---|---|
> | 「A1 是单变量改动」 | ❌ LOS 的清单还**少了一批真实模块**（清单差集 66 条；按实机 `lsmod` 折算，**41 个真会漏加载**）。A1 等于「换二进制 + 保留一份有错误的清单」 |
> | 「A1 保留 LOS 的索引文件不会造成 CRC 问题」 | ❌ 更硬的问题在这里：`modules.alias` / `modules.dep` / `modules.softdep` / `modules.blocklist` **也全是 A16 生成的**。autoload 与依赖解析全靠它们，`.ko` 换对了也白搭 |
> | 「A2 会把 stock 私有模块带进 LOS」 | ❌ PixelOS 的模块与 stock **逐字节相同**（461/461、402/402），五个索引文件 md5 也相同。A2 加载的就是同一批出货二进制 |
>
> **新推荐（A2+）**：三处**整目录替换**，零手工编辑——
>
> ```
> $K/vendor_ramdisk/lib/modules/     ← 整目录（461 .ko + 5 索引）
> $K/vendor_dlkm/lib/modules/        ← 整目录（402 .ko + 5 索引）
> $K/system_dlkm_flatten/            ← 整目录（103 .ko + 索引）
> $K/system_dlkm/                    ← 不动（与 PixelOS 逐字节相同，已正确）
> ```
>
> 于是 §0 表格的第 4/5/6 行（「删 8 条悬空、去重 195 条」）**全部作废**——整目录替换后清单与索引自然正确，不需要任何手工删改。手写清单正是第三个缺陷的成因，不要再手工编辑。
>
> **更强的验收判据**（替代「门禁 PASS」）：替换后上述三处应与 PixelOS 对应目录**逐字节相同**。实机已验证 PixelOS 的这三处就是启动成功的那一份（抽样 40 个 `.ko` + 5 个索引 md5 全同）。
>
> **LOS 缺的模块里真正会被加载的 41 个**集中在：小米私有监控/调度（`mi_*`、`mimon`、`miscore`、`rtg`、`vip_sched`、`task_attribute`、`perf_actuator`）、音频（`wcd937x_dlkm` / `wsa885x_i2c_dlkm` / `aw882xx_dlkm`）、触控与 USB-C 开关（`sia91xx_dlkm` / `fsa4480_i2c`）。
> **注意**：`qcom-cpufreq-hw`、`i2c-qcom-geni`、`spi-geni-qcom`、`phy-msm-snps-eusb2`、`qpnp-lcdb-regulator` 这五个**实机都没加载**，不要把它们当必需项。
>
> 详见 `../pixelos-cross-reference-2026-11-02.md` §6.4 / §9。

---

## 0 一页速览

| # | 位置（构建树内） | 现状（实测） | 目标 | 动作 |
|---|---|---|---|---|
| 1 | `$K/vendor_ramdisk/*.ko` | 461 个，**405** 个 CRC=`0xe976b219` | 461 全 `0x797f2b3e` | 用 stock 同名覆盖 405 个 |
| 2 | `$K/vendor_dlkm/*.ko` | 402 个，**366** 个错配 | 402 全对 | 覆盖 366 个 |
| 3 | `$K/system_dlkm_flatten/*.ko` | 103 个，**102** 个错配 | 103 全对 | 覆盖 102 个 |
| 4 | `$K/vendor_ramdisk/modules.load` | 150 条：8 悬空 + 3 重复 | 139 条、全可加载 | 删 8、去重 3 |
| 5 | `$K/vendor_dlkm/modules.load` | 569 条：8 悬空 + 195 重复 | 366 条、全可加载 | 删 8、去重 195 |
| 6 | `$K/system_dlkm_flatten/modules.load` | 82 条，1 悬空（`tls.ko`） | 81 条 | 删 1 |
| — | `$K/system_dlkm/`（版本化目录） | **103/103 已正确** | 不动 | 无 |

**实测结论（决定性）**：两侧 `vendor_dlkm` 的 **402 个 `.ko` 名字集合完全相同**（共有 402 / 仅 LOS 有 0 / 仅 stock 有 0），`vendor_ramdisk` 同为 461/461。替换后 `vendor_ramdisk` 461 个、`vendor_dlkm` 402 个 `.ko` **与 stock 逐字节完全相同**（405 替换 + 56 本来就相同 / 366 替换 + 36 本来就相同），且**文件名单 md5 替换前后一致**。所以「替换」不新增也不删除任何模块文件，只是把同名文件换成正确世代 —— 这就是「不会把 stock 私有模块带进 LOS」的直接证据。

---

## 1 修复策略选型

| | A1 · stock 模块替换（最小变更） | A2 · stock 整包对齐 | B · 用 6.12.69 源码重建 | C · 混合（重建开源部分 + 其余取 stock） |
|---|---|---|---|---|
| 做法 | 只换 `.ko`；保留 LOS 的 6 个元数据文件与清单（清单只删悬空/去重） | 换 `.ko` + `modules.alias/dep/softdep/blocklist/load/load.recovery` 全部取 stock | 拉 6.12.69 GKI + SM8850 vendor 源码，用同一份 `.config` 重编 | 开源部分重编，闭源部分取 stock |
| 离线可验证性 | **已实测 PASS**（§2 实测 3） | **已实测 PASS**（≡ stock 集合，§2 实测 2） | 无法验证：无源码 | 无法验证 |
| 可重复性 | 高：模块当 prebuilt 入库，替换脚本幂等 | 高：整目录覆盖，diff 为空 | 依赖工具链/配置完全一致才有意义 | 低：两套构建混用 |
| 许可面 | 不变。BoardConfig 已声明内核取自原厂（`TARGET_NO_KERNEL_OVERRIDE := true` + `PRODUCT_COPY_FILES kernel:kernel`），模块同源 | 同 A1 | 需小米开源包；SM8850 vendor 驱动未公开 | 同 B |
| 内核升级维护成本 | 每次升级整批换 + 门禁卡住 | 同 A1 | 低（可重编） | 中 |
| 会不会把 stock 私有模块带进 LOS | **不会新增文件**（名单 md5 相同、461/402 逐字节相同）；但**会改变加载集合**（见下） | 同左，且加载集合直接等于原厂 | — | — |
| 本次可行性 | **可行** | 可行 | **不可行** | 不可行 |

**A1 与 A2 的唯一差别是「用谁的 `modules.load`」**（元数据 `alias/dep/softdep/blocklist` 按模块名索引、与 KMI 世代无关，A1 保留 LOS 的不会造成 CRC 问题）：

| | LOS 清单（A1，清理后） | stock 清单（A2） | 差 |
|---|---|---|---|
| `vendor_ramdisk` 唯一条目 | 139 | 169 | stock 多 30：含 `gcc-sm4450` / `gcc-chora` / `dispcc-*` / `camcc-*` / `videocc-chora` / `qnoc-*` / `tcsrcc-chora` / `qcom-cpufreq-hw` 等板级时钟与电源域 |
| `vendor_dlkm` 唯一条目 | 366 | 402 | stock 多 36：含 `camcc-*` / `debugcc-*` / `gpucc-*` / `i2c-qcom-geni` / `phy-msm-snps-hs` 等 |

> **推荐：先 A1，A2 留作第二刀。**
> 理由：A1 是**单变量**改动（只改模块世代，不改加载集合），符合 `qa-matrix-v4.md` §8「单变量修复」纪律；A2 同时改了「加载哪些模块」，一旦出问题无法归因。若 A1 后能起但功能不全（屏幕/相机/充电异常），再单独切 A2 —— 那时 A2 就是第二变量，可归因。
> **B/C 本轮不采用**：`$K` 里只有 `kernel-headers`（BoardConfig.mk:30），没有 SM8850 vendor 驱动源码；且重建出的 `.ko` 的 `module_layout` CRC 由内核源码+`.config`+工具链共同决定，必须与 `0x797f2b3e` 完全一致才可用，无源码时无法保证，混编还会引入 vermagic 后缀差异（`-abogki561813157-4k`）。留作内核升级后的长期方案。

---

## 2 先上门禁，再动手

`_work/kmi-gate.sh` 已实测通过。四查：**C1** 每个 `.ko` 的 `module_layout` CRC = 内核期望值（**硬门禁**）；**C1b** 每个 `.ko` 的 vermagic 版本段是否等于期望 KMI（仅告警）；**C2** `modules.load` 每条能在目录内找到（**硬门禁**）；**C3** `modules.load` 无重复（仅告警，`--strict-dup` 升 FAIL）。集合名取「最小唯一路径后缀」，两个都叫 `lib/modules` 的目录会显示成 `los/lib/modules` / `stock/lib/modules`。

**实测记录**（完整日志 `_work/gate-all.log`，复跑 `_work/wsl-gate-all.sh`）：

| 被测集合 | C1 CRC | C2 悬空 | C3 重复 | 判定 | exit |
|---|---|---|---|---|---|
| LOS `vendor_boot`（461） | 56/461 → **405 不符** | 142/150 → **8 悬空** | 147/150 → **3 重复** | **FAIL** | 1 |
| LOS `vendor_dlkm`（402） | 36/402 → **366 不符** | 561/569 → **8 悬空** | 374/569 → **195 重复** | **FAIL** | 1 |
| LOS `system_dlkm/flatten`（103） | 1/103 → **102 不符** | 81/82 → **1 悬空** | 82/82 → 0 | **FAIL** | 1 |
| stock `vendor_boot`（461） | 461/461 | 172/172 | 169/172 → 3（WARN） | **PASS** | 0 |
| stock `vendor_dlkm`（402） | 402/402 | 665/665 | 402/665 → 263（WARN） | **PASS** | 0 |
| stock `system_dlkm/flatten`（103） | 103/103 | 82/82 | 82/82 | **PASS** | 0 |
| **修复后** `vendor_boot`（461） | 461/461 | 139/139 | 139/139 | **PASS** | 0 |
| **修复后** `vendor_dlkm`（402） | 402/402 | 366/366 | 366/366 | **PASS** | 0 |
| LOS `system_dlkm/` 版本化目录（103） | 103/103 | 82/82 | 82/82 | **PASS** | 0 |

**C1b 的实测读数（旧世代一眼可辨）**：LOS `vendor_boot` 的 vermagic 分布是 `6.12.23-android16-5-gd8653a69a3aa-mi-4k ×405` + `6.12.69-android16-6-4k ×56`；stock 是 `6.12.69-android16-6-4k ×461`。LOS `flatten` 的旧世代是 `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k ×102` —— **三处错配的旧 vermagic 还各不相同**，说明是三次不同来源的拷贝，不是一次统一的降级。

> **C3 为什么默认 WARN**：原厂 stock 的 `vendor_dlkm` `modules.load` 是 665 条 / 唯一 402 条 —— **原厂自带 263 条重复且能正常开机**。重复不阻塞启动，做成硬门禁会误杀合法配置。LOS 的 195 条重复同样不是启动失败的原因，但它让「清单条数看起来比实际多」，正是本次事故里被反复误用的那种「看起来一致」，所以保留告警。
> **C1b 为什么默认 WARN**：`CONFIG_MODVERSIONS=y` 时内核 `same_magic()` 只比较 vermagic 第一个空格**之后**的标志位，版本段被跳过。实测模块 vermagic 是 `6.12.69-android16-6-4k`，而内核 banner 是 `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`，版本段本来就不同且能正常加载。真正卡住加载的是 C1 的 CRC；「内核换了模块没换」由 `-K` 抓内核 banner，不靠 C1b。
>
> **与 `scripts/maintain/verify_kernel_modules.sh` 的分工**：那个脚本查**构建产物** `out/target/product/pandora/`、判据是 `strings | grep vermagic`；本门禁查**源目录** `$K/`、判据是 `module_layout` **CRC 本身**（内核 `check_version()` 真正比对的值）。两者互补，但 **vermagic 相同不保证 CRC 相同**（同 KMI 下改 `.config` 就可能变），建议产物侧也换成 `kmi-gate.sh`。

接入构建：把下面这行放在 `m` / `brunch` 打包之前（出包脚本或 CI 的 pre-package 步骤）：

```bash
_work/kmi-gate.sh -K out/target/product/pandora/boot.img \
    $K/vendor_ramdisk $K/vendor_dlkm $K/system_dlkm_flatten || exit 1
```

### 2.1 修复流程已在离线阶段跑通（不是纸面推演）

把 §3 的 S2–S5 **逐字**在临时组装的目录树上执行（`fixed-*` 已换好 `.ko`，但 `modules.load` 故意换回 LOS 原版），再跑门禁，实测：

| 步骤 | 输入清单条数 | 执行 §S5 后 | 门禁结果 |
|---|---|---|---|
| `vendor_ramdisk` | 150 | **139** | C1 461/461 · C2 139/139 · C3 139/139 → PASS |
| `vendor_dlkm` | 569 | **366** | C1 402/402 · C2 366/366 · C3 366/366 → PASS |
| `system_dlkm_flatten` | 82 | **81** | C1 103/103 · C2 81/81 · C3 81/81 → PASS |

三集合汇总 **PASS，exit=0**（复跑 `_work/wsl-gate-runbook-check.sh`）。本手册的 S2–S6 命令链是**可执行且自洽**的，不是「看起来对」。

---

## 3 逐步骤操作

### S0 备份（不可跳过）
- **命令**：`cp -a $K $K.bak-$(date +%Y%m%d-%H%M)`（若 `$K` 是 git 仓库：`git -C $K tag pre-kmi-fix`）
- **输入**：当前 `$K` 全目录 · **输出**：`$K.bak-*` 或 tag
- **校验点**：`du -sh $K.bak-*` 与 `du -sh $K` 一致；`ls $K.bak-*/vendor_ramdisk/*.ko | wc -l` = 461

### S1 取得 stock 模块（只读源，不要复用中间产物）
- **命令**（构建机上）：
  ```bash
  python3 _work/wsl_extract_part.py --out /root/work/gstack/qa/src vendor_boot vendor_dlkm system_dlkm
  python3 _work/wsl-vb2cpio.py /root/work/gstack/qa/src/stock_vendor_boot.img /root/work/gstack/qa/src/stock_vb.cpio
  mkdir -p /mnt/stock_vb && (cd /mnt/stock_vb && cpio -idm --quiet < /root/work/gstack/qa/src/stock_vb.cpio)
  mkdir -p /mnt/stock_vd && mount -t erofs -o loop,ro /root/work/gstack/qa/src/stock_vendor_dlkm.img /mnt/stock_vd
  mkdir -p /mnt/stock_sd && mount -t erofs -o loop,ro /root/work/gstack/qa/src/stock_system_dlkm.img /mnt/stock_sd
  ```
- **输入**：`pandora-ota_full-OS4.0.5.0.XBLCNXM-*.zip`（9 GB，`payload.bin` 在 zip 内为 STORED，裸偏移 5173）
- **输出**：`stock_vendor_boot.img` 96 MB / `stock_vendor_dlkm.img` 57 MB / `stock_system_dlkm.img` 17 MB；解出后 `/mnt/stock_vb/lib/modules/`（461 `.ko` + 6 个元数据文件）、`/mnt/stock_vd/lib/modules/`（402 `.ko`）、`/mnt/stock_sd/flatten/lib/modules/`（103 `.ko`）
- **校验点**：三个文件大小 = 100663296 / 59584512 / 17281024 字节；`ls /mnt/stock_vb/lib/modules/*.ko | wc -l` = **461**，`/mnt/stock_vd/lib/modules/*.ko` = **402**
- **坑**：stock 的 `vendor_dlkm`/`system_dlkm` 是 EROFS，`dump.erofs` 该版本没有 `--cat`，必须 `mount -t erofs`；LOS 侧两个是 ext4，用 `mount -o loop,ro` 或 `debugfs -R dump`

### S2–S4 替换三处 `.ko`（同一段脚本，`$SRC`/`$DST` 各换一次）
- **命令**（`cmp -s` 相同就跳过，所以幂等、可重复跑）：
  ```bash
  n=0; for f in $SRC/*.ko; do b=$(basename "$f")
    cmp -s "$f" "$DST/$b" || { cp -f "$f" "$DST/$b"; n=$((n+1)); }; done; echo "替换 $n"
  ```
- **三对路径与期望替换数**（依次对应 S2 / S3 / S4）：
  | `$SRC` | `$DST` | 期望替换数 | 文件数不变 |
  |---|---|---|---|
  | `/mnt/stock_vb/lib/modules` | `$K/vendor_ramdisk` | **405**（461 − 56 本来就相同） | 461 |
  | `/mnt/stock_vd/lib/modules` | `$K/vendor_dlkm` | **366**（402 − 36） | 402 |
  | `/mnt/stock_sd/flatten/lib/modules` | `$K/system_dlkm_flatten` | **102**（103 − 1） | 103 |
- **校验点**：三次 `echo` 的数分别 = **405 / 366 / 102**；三次 `ls $DST/*.ko | wc -l` 分别 = **461 / 402 / 103**（名单不变，不新增不删除）
- **红线**：`$K/system_dlkm/`（版本化目录，103 个）**一个字节都不要动** —— 它 103/103 已正确（见 §2 实测表最后一行）

### S5 修 3 个 `modules.load`
```bash
# 1) vendor_ramdisk：150 → 142（删 8 悬空）→ 139（去重 3）
cd $K/vendor_ramdisk
for m in mem_object qcom_tzmem mi_schedule metis migt miloadtrace mi_mem_epoll mi_mem_limit; do
  sed -i "/^${m}\.ko$/d" modules.load; done
awk '!seen[$0]++' modules.load > .t && mv .t modules.load
wc -l modules.load      # 期望 139

# 2) vendor_dlkm：569 → 561 → 366
cd $K/vendor_dlkm
for m in bcl_soc binder_prio common mca_pbb miwill nvmem_qfprom qcom_cache_allocation quic; do
  sed -i "/^${m}\.ko$/d" modules.load; done
awk '!seen[$0]++' modules.load > .t && mv .t modules.load
wc -l modules.load      # 期望 366

# 3) system_dlkm_flatten：82 → 81（tls.ko；内核 CONFIG_TLS is not set，本来就没编出来）
cd $K/system_dlkm_flatten && sed -i '/^tls\.ko$/d' modules.load && wc -l modules.load   # 期望 81
```
- **校验点**：三个 `wc -l` = **139 / 366 / 81**；且 `grep -c '^$'` 全为 0
- **`modules.load.recovery` 不要动**：实测两侧该文件**逐字节相同**（7778 B，466 条 / 唯一 455 / 悬空 0），本来就是好的
- **16 条悬空的定性（实测，结论：删掉是对的，不需要补）**：
  - `vendor_boot` 8 条（`mem_object` `qcom_tzmem` `mi_schedule` `metis` `migt` `miloadtrace` `mi_mem_epoll` `mi_mem_limit`）：**两侧任何分区都没有对应文件**，且**在两侧任何 `modules.dep` 里都没有条目** —— 这一版构建从未产出过它们，是清单里的脏数据。
  - `vendor_dlkm` 8 条：`bcl_soc` / `common` / `nvmem_qfprom` 这 3 个**文件存在于 vendor_boot ramdisk**（但两侧都不在任何 `modules.load` 里 → 从不加载）；`binder_prio` / `mca_pbb` / `miwill` / `qcom_cache_allocation` / `quic` 这 5 个**两侧任何分区都不存在**。8 条在 `modules.dep` 里**全部没有条目**，但 5 条在 `modules.alias` 里有指向它们的别名（如 `alias rtnl-link-miwill miwill`、`alias of:N*T*Cqcom,qfprom nvmem_qfprom`）→ 说明这些驱动曾在**模块构建阶段**存在，产物没进任何分区。结论：删。若刷机后发现对应功能缺失，再回小米开源包核对（见 §7）。
  - 注意 `modules.dep` 只覆盖 416/461 个文件，**不能单凭「dep 里没有」断定文件不存在** —— 本次结论是「dep 无条目」+「三个分区逐盘核对无文件」两条一起得到的。

### S6 跑门禁（此时必须 PASS）
```bash
_work/kmi-gate.sh -K out/target/product/pandora/boot.img \
    $K/vendor_ramdisk $K/vendor_dlkm $K/system_dlkm_flatten
```
- **校验点**：exit 0；报表三行全 PASS；`vendor_ramdisk` 的 `CRC 分布` 只剩 `0x797f2b3e=461`（不应再出现 `0xe976b219`）
- **反证**：此时若把 S2~S4 回滚任意一个，门禁必须重新 FAIL —— 这一步本身就是「门禁有效」的证明

### S7 重新构建与打包
- **命令**：`mka bacon`（或 `brunch pandora`）
- **校验点**：构建日志无 `MODVERSIONS`/`vermagic` 警告；`out/target/product/pandora/vendor_boot.img` 与 `vendor_dlkm.img` 时间戳更新
- **不要**清 `out/` 全量重建（会掩盖「旧 `.ko` 残留在 out 里」这类问题）；但**必须**确认 `out/.../vendor_ramdisk/lib/modules/` 下没有 `0xe976b219` 的残留

### S8 产物对拍（出包前最后一道）
- **命令**：
  ```bash
  python3 _work/wsl-vb2cpio.py out/target/product/pandora/vendor_boot.img /tmp/out_vb.cpio
  mkdir -p /tmp/out_vb && (cd /tmp/out_vb && cpio -idm --quiet < /tmp/out_vb.cpio)
  _work/kmi-gate.sh /tmp/out_vb/lib/modules
  ```
- **校验点**：对**打包产物**（不是源目录）跑门禁，必须 PASS；`.ko` 计数 461、`modules.load` 139 条
- **理由**：源目录对了不等于镜像里对了 —— `find-copy-subdir-files` 会把整个目录搬进去，历史上正是这种「看起来对了」的环节出错

---

## 4 回滚方案

| 触发条件 | 回滚动作 | 回到的状态 |
|---|---|---|
| S6 门禁不过 | `rsync -a --delete $K.bak-*/ $K/`（或 `git -C $K reset --hard pre-kmi-fix`） | 修改前的 `$K`，与本次事故复现时的构建完全一致 |
| S7 构建失败 | 同上，然后 `mka installclean` 再编 | 同上 |
| 刷机后不进系统 | 只回滚 `$K` 后重建**不够**——设备上已经是新镜像。用 `fastboot flash vendor_boot`/`vendor_dlkm`/`system_dlkm` 刷回**原厂**对应分区（原厂镜像从 OTA `payload.bin` 提，命令见 S1），或整套刷回 `pandora-ota_full-OS4.0.5.0.XBLCNXM` | 原厂可开机状态 |
| 刷机后能起但功能异常 | **不要**整体回滚。先按 §1 的 A1→A2 单变量推进（切 stock 清单），再判断 | — |

**回滚到「哪个状态」的硬要求**：回滚后 `$K/vendor_ramdisk/*.ko` 中 `0xe976b219` 的计数必须回到 **405**、`vendor_dlkm` 回到 **366**。这是判断「真的退回去了」而不是「退到某个中间态」的唯一客观判据 —— 用 `kmi-gate.sh` 跑一次，应当重新 FAIL 并报出 405/366/8/195。

---

## 5 刷机后验收判据

**不以「看到 launcher」为通过。** 逐条打勾，缺一条即判未通过：

| # | 判据 | 命令 | 期望 |
|---|---|---|---|
| 1 | 系统起来 | `adb shell getprop sys.boot_completed` | `1`，且 ≥15 分钟内无回退 |
| 2 | **无版本冲突** | `adb shell dmesg \| grep -E "disagrees about version of symbol\|no symbol version for"` | **0 行**（这条是本次故障的直接指纹） |
| 3 | 无模块加载失败 | `adb shell dmesg \| grep -iE "failed to load module\|-ENOEXEC\|Unknown symbol"` | 0 行 |
| 4 | 模块数量粗筛 | `adb shell cat /proc/modules \| wc -l` | **≥ 300**。这只是粗筛（低于 300 说明大面积未加载），精确判据用第 5 条 |
| 5 | 清单逐条对账 | 见下 | 缺口全部有解释 |
| 6 | 关键子系统在 | `adb shell lsmod \| grep -E "^(msm_drm\|msm_kgsl\|qcom_q6v5_pas\|rmnet_core\|zram)\b"` | 全部命中（这 5 个是举例，可按本机硬件替换） |
| 7 | 不是软重启侥幸 | 关机再开机（**不是** `fastboot reboot`）×2，每次重复 1–4 | 全通过 |
| 8 | 掉电后仍可起 | 强制断电重启 1 次，重复 1–4 | 全通过 |
**第 4/5 条的对账方法**（不靠感觉）：
```bash
# /proc/modules 用下划线模块名；modules.load 用带连字符的文件名 → 先归一化再比
adb shell cat /proc/modules | awk '{print $1}' | tr '_' '-' | sort -u > /tmp/loaded.txt
sed 's/\.ko$//' "$K/vendor_dlkm/modules.load" | sort -u > /tmp/want.txt
comm -23 /tmp/want.txt /tmp/loaded.txt      # 「清单有、实际没加载」——每一行都要有解释
```
预期：`vendor_boot` 那 139 条多数会以「已内建/已加载」形式出现，不必然全在 `/proc/modules`；但 **`vendor_dlkm` 的 366 条里未加载的必须逐条给出原因**（被 blocklist 挡、依赖未满足、硬件不存在等）。一条都解释不了 ⇒ 判未通过。

---

## 6 反向复现（证明「修好了」而不是「碰巧好了」）

三级证据，从零成本到高成本，前两级**不需要设备**：

1. **构建期反证（零刷机，必做）**：同一份 `kmi-gate.sh`，在**未修复**的 `$K` 上必须 FAIL 且报出 405/366/8/195；在**修复后**的 `$K` 上必须 PASS，两次都留档。这条排除「碰巧」—— 门禁读的是 CRC 本身，不是现象。**加 `-K boot.img` 后同时抓「内核换了、模块没换」**（反例实测见 §7），正是本次事故的形态。
2. **产物级反证（零刷机）**：用 S8 的方法对**旧包**（`UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images/`）跑门禁 → 必须 FAIL；对新包 → 必须 PASS。证明差异真的进了镜像。
3. **设备级反向复现（需设备，一次）**：把**只回滚模块**（S2~S5 全部撤销、其余不动）的构建刷进去 → 必须复现**同一类**症状（同类 = 都卡 bootanimation，不是重启循环与卡动画互换）。正向 2/2、反向 2/2 才算成立；只做正向等于没做因果验证。**对照设计**：反向臂只改 `.ko` 与 `modules.load`，`fstab`/`bootconfig`/`dtbo`/`userdata` 全部不动；若反向臂没复现，说明根因判断有误，本手册的修复即使「有效」也不可采信。

---

## 7 复跑入口与已知局限

**复跑（Windows → WSL；`/tmp` 会被清空，`/root` 跨重启持久——这正是 stage 放 `/root/work/gstack/` 的理由）**
```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 -u root -- bash "/mnt/c/…/deliverables/gstack/_work/wsl-gate-all.sh"
```
`wsl-gate-all.sh` = `wsl-gate-setup.sh`（从**只读源**重建 LOS/stock/fixed 三组模块集，落 `/root/work/gstack/qa/`）+ `wsl-gate-test.sh`（3 组实测 + 7 组边界/专项用例）。全程不改 `docs/`、`device-trees/`、`UotanToolbox_*/`、根目录镜像。

**边界与专项用例实测**：空目录 → FAIL(1)；不存在的目录 → FAIL(1)；无参数 / 未知选项 / `-K` 指向不存在的文件 → 2；`-n/--no-load` → CRC-only PASS；`--strict-dup` 下 stock FAIL（263 重复）；`--strict-vermagic` 下 LOS FAIL（405 条旧 vermagic）；两个都叫 `lib/modules` 的目录在报表里正确显示为 `los/lib/modules` 与 `stock/lib/modules`。

**`-K` 抓半迁移实测（本次事故形态）**：`-K boot.img` 正例 → 内核 banner `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k` 校验 PASS、集合全 PASS；反例把期望 KMI 设成旧世代 `6.12.23-android16-5` → 立刻报「内核 banner 校验 = FAIL」，同时 C1 报 461 个 CRC 不符，**一次运行就把「内核换了、模块没换」显形**。

**未取得 / 卡在哪**
- **未刷机验证**：无设备。「修复后能否真正开机」仍是**未验证**，§5 的 8 条判据全部待执行 —— 本手册保证的是「模块与内核 KMI 一致、清单无悬空」，是必要条件不是充分条件。A1/A2 的模块在 LOS init 与 SELinux 下是否被拒（`avc: denied`）同样只有设备上能看到。
- **内核期望 CRC `0x797f2b3e` 的独立复算**：沿用已定案值。内核 Image 无符号表，无法直接从 `__kcrctab` 读出；`check_kmi.py` 用的是「在 Image 中唯一命中」的启发式，本轮未重做。要独立确认需 `vmlinux` 或设备。
- **`tls.ko` 为何出现在 LOS flatten 清单**：已证实内核 `# CONFIG_TLS is not set`（`los_kconfig.txt:1147`）、该文件两侧都不存在、stock 的 flatten 清单不含它；推测抄自通用 GKI 清单，**未追溯来源**。
- **vendor_dlkm 那 5 个两侧都不存在的模块**是否曾是必需模块：未验证，只能删；若刷机后发现功能缺失，回小米开源包核对。
- **`vendor_ramdisk` 322 个「孤儿」`.ko`**（文件在、清单里没有）：stock 侧同样有 292 个，属 GKI ramdisk 常态，**不构成缺陷**；仅记录，未处置。
