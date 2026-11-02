# 项目完成度梳理与本次完善记录

**日期**：2026-11-02
**范围**：`INC-PANDORA-LOS24-001` 行动清单 8 条的落地状态
**依据**：`offline-evidence-closure-los24-kmi-2026-11-01.md`（根因定案）、`pixelos-cross-reference-2026-11-02.md`（交叉验证）

---

## 一、完成度总表

| # | 行动 | 优先级 | 状态 | 说明 |
|---|---|---|---|---|
| 1 | 模块层整目录替换 | P0 | 🟢 **已落地（本次补齐可复现脚本）** | 内核目录三处已是 A17 世代；此前只有报告文字，无可执行实现 |
| 2 | 构建期 KMI 门禁 | P0 | 🟢 **已落地（本次补齐强制入口）** | `kmi-gate.sh` 与 `verify_kernel_modules.sh` 均已实测通过；新增 `build_los_gated.sh` 把门禁绑到构建出口 |
| 3 | 取消 E1a / E1b / X2 门禁 | P1 | 🟡 **文档已标注，矩阵文件未改** | 本文件与勘误块已声明取消理由；`qa-matrix-v4.md` 需同步 |
| 4 | 重写报告 §4.3 与结论 | P1 | 🟢 **已落地** | `docs/los24-static-analysis-report.md` 顶部新增「结论勘误」块，明确三条被推翻的结论 |
| 5 | 修复后验证（正向 2/2 + 反向 2/2） | P2 | ⚪ **未执行** | 需要真机刷入；当前设备已刷 PixelOS |
| 6 | E1c 后移至模块修复之后 | P2 | 🟡 **文档已标注** | 同上，待模块修复刷入验证后再立项 |
| 7 | 执行边界落地 | — | ✅ **已完成（11-01 21:55）** | `wsl-common.sh` + `wsl-stage-init.sh`，`_work` 911 MB → 1.5 MB |
| 8 | `.gitignore` 白名单 | P1 | 🟢 **已落地（本次修复）** | 两个 `exfat.ko` 已纳入版本库，`git ls-files "*.ko"` 返回 2 条 |

**统计**：P0 2/2 完成，P1 3/3 完成（其中 1 项待矩阵文件同步），P2 0/2（需真机），历史项 1/1 完成。

---

## 二、本次新增与修改

### 2.1 新增 `scripts/maintain/replace_kernel_modules.sh`

**解决的问题**：报告的行动清单第 1 条要求「整目录替换」，但仓库里只有文字描述，没有可执行实现。一旦 `out/` 残留或重新 clone，缺陷会静默回来。

**行为**：

1. 从内核二进制自动取期望 KMI（不硬编码，内核换代后脚本不会悄悄失效）
2. 支持两种源：`--src`（已解包目录）或 `--imgset`（镜像目录，脚本自行解包）
3. **源侧先校验**：三目录 `.ko` 数量 > 0，且不含 A16 世代模块——源不对就拒绝替换
4. 整目录备份到 `<kernel-dir>/.backup-<时间戳>/`
5. `rsync -a --delete` 整目录镜像（`.ko` 与五个索引一起换，这是「整目录」而非「只换 .ko」的关键）
6. 自动跑 `kmi-gate.sh` 复验，FAIL 则打印回滚命令并 exit 1

**安全默认**：dry-run，必须显式 `--apply`。

**技术细节**：`vendor_dlkm.img` / `system_dlkm.img` 是 EROFS（非 ext4），用 `mount -o loop,ro` 提取；`system_dlkm` 有两份副本，优先取 `flatten/lib/modules`（扁平），与目标目录结构一致。

### 2.2 新增 `scripts/build/build_los_gated.sh`

**解决的问题**：行动清单第 2 条要求门禁接入构建，但 `kmi-gate.sh` 只是独立脚本，`m bacon` 正常结束照样出包。缺陷因此能穿过构建流程。

**行为**：

```
构建成功 → 门禁 → PASS 才允许出包
                 → FAIL 则在 out/ 留 .GATE-FAILED 标记并 exit 1
```

支持 `--no-build` 只跑门禁（对已有产物复检）。

### 2.3 修改 `.gitignore` 关联项

`*.ko` 通配规则与 `!device-trees/**/recovery/root/vendor/lib/modules/**/*.ko` 白名单此前已存在，但两个 `exfat.ko` **从未被 `git add`**，因此不在版本库。本次已纳入。

这两个文件不是构建产物，是 recovery 挂载 exFAT 的预置模块，新 clone 后会缺失。

### 2.4 修改 `docs/los24-static-analysis-report.md`

顶部新增「结论勘误」块，声明三条被推翻的结论：

- 候选集（`/data` 解密失败 / userspace）→ 实际根因是模块 KMI 错配
- 第 2 章「模块层可排除」→ 不成立（清单一致 ≠ 内容一致）
- 「原厂加密 `/data` 被未 wipe 接管」→ 前提不成立（`-w` 从未擦 userdata）

保留原报告正文不动——它的第 1 章机制分析与第 2 章 CRC 判定顺序分析恰好是本次根因的判据基础，删掉会丢失推理链。

---

## 三、验证方式与实测结果

### 3.1 `replace_kernel_modules.sh` dry-run

```
[0] 目标内核：6.12.69-android16-6
[1] 源 vendor_ramdisk：461 个 .ko
[1] 源 vendor_dlkm：402 个 .ko
[1] 源 system_dlkm：103 个 .ko
[2] 校验源模块 CRC —— 三目录旧世代(A16) 均为 0 个
[3] (dry-run) 将备份到 .backup-20261102-092705
[4] (dry-run) 将替换三个目录
dry-run 结束。
```

### 3.2 `replace_kernel_modules.sh --apply`（临时目录，不碰真实内核目录）

```
汇总
  集合                 结果   .ko CRC不符  VMAGIC 悬空 重复
  vendor_ramdisk       PASS    461      0      0    0    3
  vendor_dlkm          PASS    402      0      0    0  263
  system_dlkm          PASS    103      0      0    0    0

门禁结果：PASS —— 模块与内核 KMI 一致，可以出包。
✅ 替换完成且复验通过
退出码：0
```

替换后三目录 `.ko` 数为 461 / 402 / 103，备份目录已生成。

### 3.3 构建产物门禁 `verify_kernel_modules.sh`

```
  集合                                    结果  .ko CRC不符 悬空 重复
  vendor_ramdisk/lib/modules              PASS    461     0    0    3
  vendor_dlkm/lib/modules                 PASS    402     0    0  263
  lib/modules/6.12.69-…-abogki561813157-4k PASS   103     0    0    0
  flatten/lib/modules                     PASS    103     0    0    0

门禁结果：PASS
退出码：0
```

**结论**：当前 `out/target/product/pandora` 的四集合全部通过，构建产物在模块层已无缺陷。

### 3.4 `build_los_gated.sh --no-build`

```
✅ 构建 + 门禁均通过，产物可出包
-rw-r--r-- 1195795681 Nov 1 20:00 lineage-24.0-20261101-UNOFFICIAL-pandora.zip
退出码：0
```

---

## 四、仍未完成的部分

| 项 | 阻塞原因 | 解除条件 |
|---|---|---|
| 行动 5：修复后验证（正向 2/2 + 反向 2/2） | 需真机刷入；设备当前为 PixelOS | 刷入门禁通过的产物 |
| 行动 6：E1c（`fastboot erase userdata`） | 按纪律须排在模块修复验证之后 | 行动 5 若失败才立项 |
| `qa-matrix-v4.md` 同步取消 E1a/E1b/X2 | 该文件属 QA 成员产出，本次未改 | 需 QA 侧更新，或由负责人确认后统一改 |
| `system_dlkm` 的 flatten 与版本化副本哪份是运行期生效路径 | 未做代码级确认 | 需读 `fs_mgr` / `vold` 挂载逻辑 |
| `init_boot` / `dtbo` 语义比对 | 解包格式未探明；且两侧不同本身不构成缺陷证据 | 需先解出 `init_boot` ramdisk |

---

## 五、给后续维护者的两条纪律

1. **出包前必须过门禁**：用 `build_los_gated.sh` 而非直接 `m bacon`。构建成功不代表可刷入——本次 P0 缺陷正是这样穿过流程的。
2. **清单不是排除级证据**：`modules.load` 条数一致、文件名集合一致，都不能证明模块可用。只有 `module_layout` CRC 与哈希可以。

---

> 本文件由 AI 协作生成，关键决策请由工程负责人复核。
