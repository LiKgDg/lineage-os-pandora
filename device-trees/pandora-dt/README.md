# Xiaomi 17 Pro (pandora / canoe / SM8850) 设备树

小米 17 Pro（产品代号 **pandora**、高通板级代号 **canoe**、SoC **Qualcomm SM8850**）
的 Linux/Android **设备树源码与可复现构建内容**。

DTS 从**真机实际运行的出厂固件（OS4.0.5.0.XBLCNXM / Android 17）中精确提取并反编译**，
再经过 `base dtb + 板级 overlay` 合并整理，用于还原设备运行时的设备树。
仓库内 `make` 即可用上游 `dtc` 重新编译出 dtb/dtbo，并通过与原厂二进制的根节点元数据对照校验。

## 为什么是反编译

小米开源分支未包含板级 dts 源。设备运行时实际使用的树只能从固件中提取：

| 来源 | 内容 | 大小 |
|---|---|---|
| `vendor_boot.img` 的 `dtb` 字段 | 12 个 SoC 基础树（Canoe / CanoeP / Whale 各变体） | 6,557,139 字节 |
| `dtbo.img`（dtbo 分区） | 2 个板级 overlay，`compatible` 均含 `qcom,canoe` | 23,068,672 字节 |

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
├── Makefile                      # make / make verify / make clean
├── dts/
│   ├── xiaomi-pandora.dts                # 【主入口】base+overlay 合并后的完整树（50,917 行）
│   ├── xiaomi-pandora-common.dtsi        # SoC 基础树（vendor_boot 内 dtb，28,567 行）
│   └── overlays/
│       └── board-pandora-overlay.dts     # 板级 overlay（dtbo 分区，25,138 行）
├── original/
│   ├── base-parts/                       # 从 vendor_boot 拆出的 12 个基础树
│   ├── dtbo-parts/                       # 从 dtbo.img 拆出的 2 个 overlay
│   └── stock-bootconfig.txt              # 原厂 bootconfig
└── scripts/
    ├── build-dtb.sh              # dtc 编译 + 打包 dtbo.img
    ├── verify-stock.sh           # 重建并与原厂根节点元数据对照
    └── mkdtimage.py              # Android dt_table 打包器（无第三方依赖）
```

## 使用

```bash
# 编译
make

# 校验（重新编译并与 original/ 中的原厂二进制对比 model / compatible）
make verify

# 清理
make clean
```

依赖：`device-tree-compiler`（dtc ≥ 1.6）、`python3`。
校验额外用到 `fdtget`（同属 device-tree-compiler 包）。

## 产物

| 文件 | 说明 |
|---|---|
| `build/canoe-base.dtb` | SoC 基础树，对应 vendor_boot 内的 dtb |
| `build/overlays/board-pandora.dtbo` | 板级 overlay |
| `build/xiaomi-pandora.dtb` | 合并后的完整树（可直接反编译阅读） |
| `build/dtbo.img` | dt_table 格式，可刷入 dtbo 分区 |

## 板级 overlay 的选择

`dtbo.img` 里有 2 个 entry，两者 `compatible` 相同：

| entry | 大小 | fragment 数 |
|---|---|---|
| `00.dtbo` | 141,842 | 45 |
| `01.dtbo` | 1,134,915 | **145** |

本仓库采用 **01**（fragment 更完整）。`00` 保留在 `original/dtbo-parts/` 供对照。

## 基础树的选择

12 个基础树对应不同 SoC 变体：

| 文件 | model |
|---|---|
| `00` / `01` | Canoe Alt. Thermal Profile (v2) SoC |
| `02` | **Canoe v2 SoC** ← 本仓库采用 |
| `03` | Canoe SoC |
| `04` / `05` | CanoeP SG (v2) SoC |
| `06` / `07` | CanoeP Alt. Thermal Profile (v2) SoC |
| `08` / `09` | CanoeP (v2) SoC |
| `10` / `11` | Whale / WhaleP SoC |

## 来源

- 固件：`pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip`
- 提取工具：`tools/payload_dump.py`（payload 解包）、`system/tools/mkbootimg/unpack_bootimg.py`
- 参考工程：[`LL-fan/xiaomi-17-pro-max-device-tree`](https://github.com/LL-fan/xiaomi-17-pro-max-device-tree)（popsicle 版本，流程一致）
