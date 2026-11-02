# 三仓发布方案（pandora 设备树）

**状态**：方案与发布物已就绪，**尚未创建 GitHub 仓库、尚未 push**。
**前提**：`D4 刷入启动未通过`，本方案发布的是**实验性移植**，README 已如实标注。
**依据**：本次只读审计（继承链 / 关键路径 / 通用配置覆盖度 / blobs 清单比对 / 许可证现状）。

---

## 一、为什么是三仓

| # | 仓库 | 内容 | 体积（apparent） | 变更频率 |
|---|---|---|---|---|
| 1 | `android_device_xiaomi_pandora` | 机型树 | **42,759 B + 4 个新增文件 ≈ 47 KB** | 低 |
| 2 | `android_device_xiaomi_sm8850-common` | 8850 家族公共配置（上游快照 + pandora 适配） | **725,220 B ≈ 710 KB** | 跟上游同步 |
| 3 | `android_device_xiaomi_pandora-kernel` | **只有提取脚本 + 清单**，无二进制 | **< 200 KB** | 低 |

**拆的理由**：三者的体积差 4 个数量级（47 KB / 710 KB / 279 MiB），生命周期也不同。
`sm8850-common` 是上游 `lolipuru/android_device_xiaomi_sm8850-common`（`lineage-24.0` 分支，
取证时 HEAD `6b1fa62...`，168 commits）的快照，上游支持 pudding / popsicle / myron / athens /
songyuan 五台机（**不含 pandora**）。合并成单仓后，每次跟上游同步都要手工 diff 184 个文件；
拆开后是 `git remote add upstream && git fetch upstream && git merge upstream/lineage-24.0`。

**反例（什么情况下该合成单仓双子目录）**：只维护 pandora 一台、永不跟上游同步、也不指望第三方复用
→ 单仓 `device/xiaomi/{pandora,sm8850-common}` 更省事，还能省掉 `lineage.dependencies` 的维护。
**判断依据只有一条：以后还同不同步 lolipuru。**

---

## 二、包含 / 排除清单

### 进 git

`*.mk` `*.bp` `*.xml` `*.prop` `*.te` `*.rc` `*.aidl` `*.kt` `*.cpp` `*.py`（提取脚本）
`README.md` `LICENSE` `NOTICE` `lineage.dependencies` `modules.load*` `manifest.sha256`

### 不进 git

| 对象 | 体积 | 理由 |
|---|---|---|
| `vendor/xiaomi/sm8850-common/proprietary/` | **638 MiB / 1741 文件** | LineageOS 通行做法：只入库 `proprietary-files.txt` + 提取脚本，blob 由使用者自提 |
| `pandora-kernel` 的二进制（`kernel` / `dtbo.img` / `*.dtb` / `*.ko`） | **279 MiB** | 小米分发物，不随源码分发；需要的人从原厂 OTA 自提 |
| `*.img` / `pandora-ota_*.zip` / `PixelOS_*` / `sysonly/` | GB 级 | 现行根 `.gitignore` 已覆盖 |

### ⚠️ 内核目录的 `.gitignore` 陷阱（必须单独处理）

主仓根 `.gitignore` 里有 `*.img`、`*.ko`、`*.dtb`、`*.zip`。而 `pandora-kernel` 的内容
**恰好全在这几类里**：

- `kernel`（无扩展名）→ **不会被忽略**，会被提交
- `dtbo.img`、`*.dtb`、402+461 个 `*.ko` → **全部被忽略**

如果直接把内核目录塞进现行仓库，会得到"**只有 kernel、没有模块**"的半残提交，而且不报错。
内核发布仓因此配了**独立 `.gitignore`**（默认忽略一切二进制，只放行白名单），
并用 `git check-ignore --no-index -v` 对 `kernel` / `vendor_dlkm/*.ko` / `dtbo.img` / `dtb/*.dtb`
逐条验证过忽略规则命中。

---

## 三、体积估算

| 方案 | git 体积 | 说明 |
|---|---|---|
| 三仓（推荐） | **< 1 MB** | 三仓合计约 0.95 MB，无 Release 也能 clone |
| 内核二进制走 Release | 资产 **~110–130 MB** | 279 MiB 打 `tar.zst`，`.ko` 可压到 ~40% |
| 内核二进制强行入 git | **280 MB+**，且每次替换模块都重写历史 | 不推荐 |
| 反例：连 blobs 一起推 | **~915 MB** | 接近 GitHub 1 GB 建议上限，每次 OTA 更新都重写 638 MiB 历史 |

无单文件超 GitHub 100 MB 硬限：实测最大 `proprietary/vendor/lib64/libQnnHtpPrepare.so` 51.8 MB、
`kernel` 41.5 MB、`dtbo.img` 23.0 MB、`qca_cld3_peach_v2.ko` 21.4 MB；**全资产 >100 MB 的文件数 = 0**。

---

## 四、许可证处理

### 现状（审计实测）

| 事实 | 结论 |
|---|---|
| 上游每个源文件自带 `SPDX-License-Identifier: Apache-2.0` + `Copyright (C) 2026 The LineageOS Project` | **上游自己的文件头，保持原样，不要改** |
| 上游仓库根**没有 LICENSE 文件** | Apache-2.0 §4(a) 要求随分发提供许可证副本 → 需补 |
| 上游零 `lolipuru` 字样、无 NOTICE | §4(d) 要求保留归属信息 → 需补 NOTICE |
| 本地快照的 `.git` 是断链符号链接 | provenance 本地推不出来，靠团队另行取证（已取得 HEAD `6b1fa62...`） |

### 做法

1. **不改任何上游文件头**（含 `Copyright (C) 2026 The LineageOS Project` 行）。
2. 两仓各补 `LICENSE`（Apache-2.0 **全文**，取自 `/usr/share/common-licenses/Apache-2.0`，
   11358 B / 202 行，未改写缩写）。
3. 两仓各补 `NOTICE`：版权声明 + 上游 URL / 分支 / HEAD / 快照时间 + 「可能落后 1 个提交」+
   §4(b) 修改声明（列到文件级）+ 商标免责。
4. 内核仓：不入 git、不走 Release 二进制，README 声明「小米分发物、版权归小米、仅个人研究」，
   与主仓 `README.md` 既有口径一致。
5. 根仓 `LICENSE`（MIT）与 `README.md` §许可证 的表述保持不变 —— 它已经写明
   `device-trees/` 沿用上游许可证。

---

## 五、推送步骤（**未执行**，由 team-lead 执行）

### 0. 前置

```bash
# 三个发布目录已就绪（不含 .git）
ls -1 /mnt/d/WSL/publish/
#   android_device_xiaomi_pandora
#   android_device_xiaomi_sm8850-common
#   android_device_xiaomi_pandora-kernel
```

### 1. 机型树

```bash
cd /mnt/d/WSL/publish/android_device_xiaomi_pandora
git init -b lineage-24.0
git add -A
git commit -m "pandora: device tree for Xiaomi 17 Pro (canoe/SM8850), experimental"
gh repo create LiKgDg/android_device_xiaomi_pandora --public \
  --description "LineageOS 24 device tree for Xiaomi 17 Pro (pandora) — experimental, boot not verified" \
  --source=. --push
```

### 2. 公共树

```bash
cd /mnt/d/WSL/publish/android_device_xiaomi_sm8850-common
git init -b lineage-24.0
git add -A
git commit -m "sm8850-common: import lolipuru lineage-24.0 (6b1fa62) + pandora adaptations"
gh repo create LiKgDg/android_device_xiaomi_sm8850-common --public \
  --description "Common device configuration for Xiaomi SM8850 family (pandora fork of lolipuru)" \
  --source=. --push

# 建议同时登记上游，便于日后同步
git remote add upstream https://github.com/lolipuru/android_device_xiaomi_sm8850-common
```

### 3. 内核（清单仓，无二进制）

```bash
cd /mnt/d/WSL/publish/android_device_xiaomi_pandora-kernel
git init -b lineage-24.0
git add -A
git status --porcelain     # 确认只收清单/脚本/README，不含 .ko/.img/.dtb/kernel
git commit -m "pandora-kernel: extraction scripts + module manifests (no binaries)"
gh repo create LiKgDg/android_device_xiaomi_pandora-kernel --public \
  --description "Kernel extraction manifests for Xiaomi 17 Pro (pandora) — no binaries, extract from stock OTA" \
  --source=. --push
```

### 4. 校验三仓可达

```bash
for r in pandora sm8850-common pandora-kernel; do
  git ls-remote https://github.com/LiKgDg/android_device_xiaomi_$r lineage-24.0
done
```

---

## 六、发布后仍需补的事（**不在本次范围内**）

1. **机型 blobs 从未生成** —— `vendor/xiaomi/pandora` 不存在，需要一台 pandora 做完整 dump，
   或用 `tools/payload_dump.py` 解全量 OTA + `gen_blob_list.py` / `gen_vendor_bp.py` 生成。
2. **211/1758（12%）条 blob 清单条目找不到实体** —— 补齐 dump 后重跑比对。
3. **触控 idc 缺失** —— `configs/keylayout/Xiaomi_Touch_Input_1.idc`。
4. **6 个树外补丁脚本未沉进设备树** —— 应把 `fix_ipa_headers` / `fix_blob_deps` /
   `fix_wfd_elfcheck` / `fix_qcwcn_common` / `fix_rildb_filegroups` / `fix_sepolicy_compat`
   的改动沉进 `sm8850-common`（多数本就是该树的配置），或提供 `patches/` + 应用步骤。
5. **`BUILD_FINGERPRINT` 的 `CP2A.260605.016` 无来源** —— 要么换成实测原厂指纹，要么在 README 说明用途。
6. **D4 启动验证** —— 未通过；修完后应在 README 更新状态表。

---

## 七、纪律声明

- 本方案**没有**任何"已验证可启动"的表述。D4 未通过是事实。
- 体积、文件数、清单条目数、行数均为实测值（`du -sb` / `find | wc -l` / `wc -l`），非估算的已注明"估"。
- 未核实项一律写"未核实"，不写"应该没问题"。
