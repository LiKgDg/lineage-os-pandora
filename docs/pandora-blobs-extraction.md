# pandora 机型专属 blobs 提取记录

> 目标：补齐 `vendor/xiaomi/pandora`——这是之前「机型 blobs 缺失」这一长期阻塞项的落地。

## 结论

从 PixelOS（pandora 同机型、已实机启动验证）的 fastboot 整包，提取出 pandora 相对
`sm8850-common` 的**专属增量 blobs**，共 **2152 条**，4.6 GB。

| 分区 | 增量条目 | 说明 |
|---|---|---|
| vendor | 771 | pandora 专属 vendor 库（.so / firmware / 专有二进制） |
| odm | 1339 | pandora 专属 ODM 定制 |
| product | 10 | 专有 app（极少） |
| system_ext | 32 | 专有组件（Qti/QCC 等） |

## 来源与依据

- **PixelOS_pandora-17.0-20261102**：pandora 同机型、A17（OS4.0.5.0 世代）、
  已实机启动验证（module_layout CRC `0x797f2b3e` 就是 PixelOS 验证过的）
- 为什么用 PixelOS 而非小米原厂 dump：PixelOS 是 A17（目标世代），
  原厂 dump（`Jiovanni-dump/xiaomi_pandora_dump`）是 A16（OS3.0.7.0），世代不对

## 提取方法（可复现）

1. 解包 PixelOS fastboot zip，取 `vendor.img` / `odm.img` / `product.img` / `system_ext.img`
   （都是 raw ext4，`debugfs -R "rdump /"` 导出）
2. `scripts/device/gen_pandora_manifest.py` 生成 `proprietary-files.txt`：
   - vendor + odm：全量增量（PixelOS 有、sm8850-common 清单无）
   - system_ext + product：只取专有命名（Qti/QCC/Pandora/CarrierConfig 等）
   - 排除：toybox/toolbox 命令符号链接、杂物扩展名、fonts/oat、断链
3. `device/xiaomi/pandora/setup-makefiles.py` 从清单生成 `pandora-vendor.mk`

## 关键判断（踩过的坑）

1. **不能全量搬**：PixelOS 完整分区 8171 文件里混着大量开源可构建内容
   （framework jar、开源 app、字体、system_ext 资源），全搬会冲突且超大
2. **不能纯扩展名过滤**：`vendor/bin/` 下 195 个是 toybox 命令符号链接
   （`cat`/`cp`/`ls` 等），指向 `toybox_vendor`，这些 AOSP 可构建，必须排除——
   否则 soong 报 `path may not contain a glob: vendor/bin/[`
3. **边界以 sm8850-common 为权威基准**：它 vendor+odm 占 93%，
   system_ext 只 107、product 只 10，说明 blobs 主体就是 vendor+odm

## 与 sm8850-common 的关系

- sm8850-common 的清单来自「17 Pro Max」（错误机型），命中 pandora 92%（1625/1758）
- pandora 的 `vendor/xiaomi/pandora` 放**增量**（common 未覆盖的 2152 条），不重复、不冲突
- `device.mk` 里已有 `inherit-product-if-exists vendor/xiaomi/pandora/pandora-vendor.mk`，
  现在这个文件终于有内容了

## 产出的文件

| 文件 | 位置 | 说明 |
|---|---|---|
| `gen_pandora_manifest.py` | `scripts/device/` + `device-trees/los24-pandora/` | 清单生成脚本 |
| `proprietary-files.txt` | `device-trees/los24-pandora/` | 2152 条清单 |
| `setup-makefiles.py` | `device-trees/los24-pandora/` | 清单→vendor.mk |
| blobs 实体（4.6 GB） | `/root/los24/vendor/xiaomi/pandora/proprietary/` | 不进 Git，走 Release |
| `pandora-vendor.mk` | `/root/los24/vendor/xiaomi/pandora/` | 由 setup 生成 |

## 待办

- [ ] blobs 4.6 GB 需通过 GitHub Release 分发（Git 单文件 100 MB 限制）
- [ ] `vendor/xiaomi/pandora` 的 Android.bp/mk 已在 WSL 树就位，需同步到仓库发布
- [ ] 构建验证：`m nothing`（接入 vendor/pandora 后是否仍绿）

## 补充：构建接入时排除了三类「非 blob」

把 blobs 接入 soong/kati 构建时，三轮报错各暴露一类必须从清单排除的文件：

| 轮 | kati 报错 | 根因 | 排除规则 |
|---|---|---|---|
| 1 | `path may not contain a glob: vendor/bin/[` | toybox 命令符号链接（`[` 等 195 个） | 指向 toybox_vendor/toolbox 的 symlink |
| 2 | `VINTF metadata found in PRODUCT_COPY_FILES` | vintf manifest 不是 blob | 路径含 vintf |
| 3 | `Prebuilt apk found: .../overlay/*.apk, use BUILD_PREBUILT` | RRO overlay 不是 blob | overlay 目录下的 .apk |

三类共排除 197 + 34 + 13 = 244 条，最终清单 2105 条。

> 其中 overlay 排除踩了个真 bug：`rel` 是相对分区路径，第一层目录前没有斜杠
> （`overlay/xxx.apk` 而非 `/overlay/xxx.apk`），用 `"/overlay/" in rel` 永远匹配不上。
> 改为 `split("/")` 判断路径段含 `overlay` 才修复。

## 补充二：构建接入的完整排查链（六轮）

把 pandora blobs 接入 soong/kati 构建，共排查六类问题，最终清单收敛到 2007 条：

| 轮 | 阶段 | 报错/问题 | 修复 |
|---|---|---|---|
| 1 | kati | `path may not contain a glob: vendor/bin/[` | 排除 toybox 符号链接（195） |
| 2 | kati | `VINTF metadata found in PRODUCT_COPY_FILES` | 排除 vintf（34） |
| 3 | kati | `Prebuilt apk: odm/overlay/*.apk` | 排除 RRO overlay（13），踩 `/overlay/` 路径判断 bug |
| 4 | kati | `Prebuilt apk: product/app/SoterService.apk` | apk 不能走 COPY_FILES，改 android_app_import |
| 5 | soong | `module "CneApp" found in multiple namespaces` | 清单解析 bug：未剥离 `;REQUIRED=`/`|sha1` 后缀 |
| 6 | （进行中） | — | — |

### 两个关键 bug（值得记）

1. **`/overlay/` 路径判断**：`rel` 是相对分区路径，第一层目录前无斜杠
   （`overlay/xxx.apk`），用 `"/overlay/" in rel` 永远匹配不上 → 改 `split("/")` 判断路径段。

2. **清单后缀未剥离**：sm8850-common 清单里条目带 `;REQUIRED=...`（依赖）和 `|sha1`
   （pinned 校验）后缀，`covered` 集合按 `split(":")` 只剥了映射目标，没剥 `;`/`|` 后缀，
   导致 98 个文件被误判为「未覆盖」重复纳入 pandora 增量，触发模块重名冲突。
   改为 `split(":")[0].split(";")[0].split("|")[0]` 三段剥离。

### 结论：blobs 的正确边界

- 只有 `.so`、firmware、专有配置、**非 overlay 的专有 apk**（走 android_app_import）是 blob
- toybox 命令、vintf、RRO overlay 都是「源码/device tree 可提供」的，不是 blob
- 这些边界之前靠 extract-utils 框架自动处理，手写脚本时容易漏
