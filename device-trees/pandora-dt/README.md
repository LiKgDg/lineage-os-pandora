# Xiaomi 17 Pro (pandora / canoe / SM8850) 设备树

小米 17 Pro（产品代号 **pandora**、高通板级代号 **canoe**、SoC **Qualcomm SM8850**）
的 Linux/Android **设备树源码与可复现构建内容**。

DTS 从**真机实际运行的出厂固件（OS4.0.5.0.XBLCNXM / Android 17）中精确提取并反编译**，
再经过 `base dtb + 板级 overlay` 合并整理，用于还原设备运行时的设备树。
仓库内 `make` 即可用上游 `dtc` 重新编译出 dtb/dtbo，并通过与原厂二进制的**根节点全属性**、
**dtbo entry 元数据**、**全树结构对账**三层校验。

重建细节、每个数字的出处、已知差异：见 [`docs/dt-rebuild-report.md`](docs/dt-rebuild-report.md)。

## 为什么是反编译

小米开源分支未包含板级 dts 源。设备运行时实际使用的树只能从固件中提取：

| 来源 | 内容 | 大小 |
|---|---|---|
| `vendor_boot.img` 的 `dtb` 字段 | 12 个 SoC 基础树（Canoe / CanoeP / Whale 各变体） | 6,557,139 字节 |
| `dtbo.img`（dtbo 分区） | 2 个板级 overlay，`compatible` 均含 `qcom,canoe` | 23,068,672 字节（dt_table 本体 1,276,853） |

## 设备概览

| 项 | 值 |
|---|---|
| 产品代号 | pandora |
| 板级 / 平台 | canoe（`ro.board.platform`） |
| SoC | Qualcomm SM8850（Canoe v2） |
| 系统 | HyperOS OS4.0.5.0.XBLCNXM / Android 17（SDK 37） |
| 内核 | GKI `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k` |
| Bootloader | Qualcomm ABL，A/B 虚拟分区，boot/vendor_boot header v4 |
| 屏幕 | 1220 × 2656，density 520 |
| super | 13,421,772,800 字节（`0x320000000`） |

## 目录结构

```
pandora-dt/
├── Makefile                      # dtb / merge / extract / verify / clean
├── dts/
│   ├── xiaomi-pandora.dts                # 【主入口】base+overlay 合并后的完整树（50,917 行）
│   ├── xiaomi-pandora-common.dtsi        # SoC 基础树（vendor_boot 内 dtb，28,567 行）
│   └── overlays/
│       ├── board-pandora-overlay.dts     # 板级 overlay entry[1]（145 fragment，25,138 行）
│       └── board-pandora-overlay-alt.dts # 板级 overlay entry[0]（45 fragment，5,797 行）
├── original/
│   ├── base-parts/                       # 从 vendor_boot 拆出的 12 个基础树（校验基准，入库）
│   ├── dtbo-parts/                       # 从 dtbo.img 拆出的 2 个 overlay
│   ├── manifest.tsv                      # 三来源 30 行清单（source/part/index/offset/size/id/rev/custom*/model/compatible/sha256）
│   └── stock-bootconfig.txt              # 原厂 bootconfig
├── docs/
│   └── dt-rebuild-report.md              # 重建与校验报告
├── extracted/                            # make extract 产物（38 MB，gitignore）
└── scripts/
    ├── build-dtb.sh              # dtc 编译 + 打包 dtbo.img（2 个 entry，可指定元数据）
    ├── merge-dtb.sh              # fdtoverlay 真实合并 + 与合并 dts 结构对账
    ├── extract-dt.sh             # 从 OTA / PixelOS 解包、拆分、反编译、生成 manifest
    ├── verify-stock.sh           # 三层深度校验
    ├── dttool.py                 # FDT / dt_table / vendor_boot 解析与对账（仅标准库）
    ├── mkdtimage.py              # Android dt_table 打包器（支持 packed 布局与 entry 元数据）
    └── in-wsl.sh                 # Git Bash 无 dtc 时自动转发到 WSL
```

## 使用

```bash
make            # 编译 dts/ → build/（4 个产物 + dtbo.img）
make merge      # fdtoverlay 合并原厂 base+overlay，并与 build/xiaomi-pandora.dtb 结构对账
make extract    # 从原厂 OTA + PixelOS 解包，重建 original/manifest.tsv 与 extracted/
make verify     # 重建 + 三层校验，任一 FAIL 退出码非 0
make clean      # 清理 build/
```

依赖：`device-tree-compiler`（dtc ≥ 1.6，需要 `fdtoverlay`）、`python3`。

`make extract` 需要源包，可用变量覆盖（默认指向仓库根目录下的两个文件）：

```bash
make extract STOCK_OTA=/path/to/pandora-ota_full-….zip \
             PIXELOS_ZIP=/path/to/Fastboot_PixelOS_….zip
```

Windows 的 Git Bash 没有 `dtc`/`fdtoverlay`，`scripts/in-wsl.sh` 会自动把命令转发到 WSL 执行；
本机已有工具链时直接本地跑。

## 产物

| 文件 | 说明 | 字节 |
|---|---|---|
| `build/canoe-base.dtb` | SoC 基础树，对应 vendor_boot 内的 dtb | 581,454 |
| `build/overlays/board-pandora-alt.dtbo` | dtbo entry[0]，与原厂**逐字节相同** | 141,842 |
| `build/overlays/board-pandora.dtbo` | dtbo entry[1]，属性级 0 差异 | 1,134,926 |
| `build/xiaomi-pandora.dtb` | 合并后的完整树（可直接反编译阅读） | 1,650,827 |
| `build/runtime.dtb` / `.dts` | `fdtoverlay` 真实合并原厂 base+overlay 的结果 | 1,651,336 |
| `build/dtbo.img` | dt_table 格式，**2 个 entry、紧凑布局**（offset `0x60` / `0x22a72`，与原厂一致） | 1,276,864 |

`dtbo.img` 的 entry 顺序必须是 `[00(whale/canoep-SG), 01(canoe/canoep)]`：bootloader 用
`androidboot.dtbo_idx` 索引这个表，本机是 `dtbo_idx=1`，顺序反了或只有一个 entry 都会让下标语义失效。
生成的是 1.2 MB 的纯 dt_table，不含 AVB 尾部；`fastboot flash dtbo` 会按分区（32 MiB）补齐，
若要用 `dd` 写分区需自行补零。

## 校验深度

`make verify` 做三类校验，全部基于二进制字节而不是字符串：

1. **根节点全属性**：枚举 `/` 上出现的所有属性名（base 7 个、overlay 5 个、合并树 7 个），
   逐个比对 `model`、`compatible`、`#address-cells`、`#size-cells`、`interrupt-parent`、
   `qcom,board-id`、`qcom,msm-id`、`xiaomi,miboard-id` 的原始字节。
2. **dtbo.img entry 元数据**：`magic`/`version`/`page_size`/`entry_count`/`hdr_size`/`entry_size`/
   `entries_offset`，每个 entry 的 `id`/`rev`/`custom[0..3]`/`dtb_size`/`offset`，以及
   **前 `total_size` 字节载荷的 md5**。原厂 23 MB 与 PixelOS 32 MB 两份镜像分别对照。
3. **三来源差异矩阵**：原厂 A17 / PixelOS / LOS 构建产物的 dtbo 逐 entry 比对。

另加**全树结构对账**（`make merge`）：节点数、属性数、排序后的节点路径集合、每个属性的原始字节。
旧版只比 4 个字符串，会漏掉 135 处属性值差异——详见报告第 8 节。

## 板级 overlay 的选择

`dtbo.img` 里有 2 个 entry，两者 `compatible` 相同：

| entry | 大小 | fragment 数 | 用途 |
|---|---|---|---|
| `00.dtbo` | 141,842 | 45 | 精简 overlay，原厂同时下发 |
| `01.dtbo` | 1,134,915 | **145** | 本仓库的运行时来源，fragment 更完整 |

两个 entry 都会被打进 `build/dtbo.img`（顺序与原厂一致）；合并运行时树用的是 **01**。

## 基础树的选择

12 个基础树对应不同 SoC 变体，只有 6 个能与 `01.dtbo` 合并成功：

| 文件 | model | msm-id | 合并 |
|---|---|---|---|
| `00` / `01` | Canoe Alt. Thermal Profile (v2) / SoC | `0x1000294` | OK |
| `02` | **Canoe v2 SoC** ← 本仓库采用 | `0x294 0x20000` | OK |
| `03` | Canoe SoC | `0x294 0x10000` | OK |
| `04`–`07` | CanoeP SG / CanoeP Alt. Thermal Profile | `0x2e7` / `0x1010295` | FDT_ERR_NOTFOUND |
| `08` / `09` | CanoeP (v2) / CanoeP SoC | `0x295` | OK |
| `10` / `11` | Whale / WhaleP SoC | `0x2d2` / `0x2d3` | FDT_ERR_NOTFOUND |

选 `02` 的依据不是 model 字符串，而是设备侧 dump：`ro.boot.dtb_idx=2`、`ro.boot.dtbo_idx=1`、
`hw-revision=20000`（完整证据链见报告第 4 节）。两个 dtbo entry 的 `id/rev/custom` 全为 0，
**只能靠 overlay 根节点的 `qcom,msm-id` 集合区分**：entry0 是 Whale/WhaleP/CanoeP-SG，
entry1 才有 `0x294`。另外 `fdtoverlay` 能叠加成功**不能**当判据——两个 overlay 的 fragment 都是
`target=<0xffffffff>` 符号引用，不绑定具体 base。

## 已知限制

- `dtc -O dts` 对「NUL 后紧跟 0-7 数字」的字符串列表输出有歧义（`\0` + `2` 会被读成 `\02`）。
  `dts/` 里已把这类值改写成逗号分隔字符串列表；`extracted/` 由 `dttool.py normalize-dts` 自动修正。
- 重建 dtb 与原厂 dtb 的字符串表打包不同（dtc 1.7 的后缀复用策略与厂商当年那版不同），实测
  `dtbo.img` 多 11 字节：载荷 md5 原厂 `a4b9b5f1f…` / 重建 `06d06918…`。把两边按 token 序列用统一
  字符串表重新序列化后结构块**逐字节相同**，所以这是纯序列化差异；entry[0] 已逐字节复现。
  这是唯一未能字节级复现的环节（要消除需换 dtc 版本，与「不引入第三方依赖」冲突）。
  `make verify` **不以 md5 相等作为门禁**：只要 `size_dt_struct` 相等、token 流语义 diff 为 0、
  entry 元数据全等，就判 `BYTES`（打印两个 md5，不计失败）。
- `make extract` 依赖 9 GB 原厂 OTA，仓库不存该文件；新克隆必须先解包才能跑完整的 `make verify`
  （`original/base-parts/*.dtb` 已入库，6.5 MB）。

## 来源

- 固件：`pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip`
- 提取工具：`tools/payload_dump.py`（payload 解包）、`scripts/dttool.py`（dtb / dt_table / vendor_boot 解析）
- 参考工程：[`LL-fan/xiaomi-17-pro-max-device-tree`](https://github.com/LL-fan/xiaomi-17-pro-max-device-tree)（popsicle 版本，流程一致）
