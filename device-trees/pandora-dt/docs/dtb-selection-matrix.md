# dtb / dtbo 选择矩阵

这张表把**文件里的静态属性**与**运行时实证**分开列，不要混用：

- 静态列（`msm_id` / `msm_rev` / `model` / `board_id`）：从原厂二进制里读出来的，任何人可复现。
- 运行时列（`runtime`）：来自**真机 dump**，是本机实际走了哪一棵的唯一直接证据。

## 基准树（`vendor_boot` 的 dtb section，12 棵）

dtb section 起点 `0x1527000`（22,179,840），总长 6,557,139 B，12 棵**首尾相接、无任何页对齐填充**；
`index` 就是 section 里的 0 基顺序，与 `original/base-parts/` 的文件名前缀一一对应（已按序 md5 核对）。

| idx | 文件 | 字节 | model（去掉 `Qualcomm Technologies, Inc. `） | compatible | `qcom,msm-id` | variant | `qcom,board-id` | 运行时 |
|---|---|---|---|---|---|---|---|---|
| 0 | `00_dtb_581542.dtb` | 581,542 | Canoe Alt. Thermal Profile v2 SoC | `qcom,canoe` | `0x1000294 0x20000` | Alt / v2 | `0x0 0x0` | 否 |
| 1 | `01_dtb_576027.dtb` | 576,027 | Canoe Alt. Thermal Profile SoC | `qcom,canoe` | `0x1000294 0x10000` | Alt / v1 | `0x0 0x0` | 否 |
| **2** | **`02_dtb_581424.dtb`** | **581,424** | **Canoe v2 SoC** | **`qcom,canoe`** | **`0x294 0x20000`** | **normal / v2** | `0x0 0x0` | **是** |
| 3 | `03_dtb_576007.dtb` | 576,007 | Canoe SoC | `qcom,canoe` | `0x294 0x10000` | normal / v1 | `0x0 0x0` | 否 |
| 4 | `04_dtb_509818.dtb` | 509,818 | CanoeP SG v2 SoC | `qcom,canoep` | `0x2e7 0x20000` | normal / v2 | `0x0 0x0` | 否 |
| 5 | `05_dtb_501152.dtb` | 501,152 | CanoeP SG SoC | `qcom,canoep` | `0x2e7 0x10000` | normal / v1 | `0x0 0x0` | 否 |
| 6 | `06_dtb_536022.dtb` | 536,022 | CanoeP Alt. Thermal Profile v2 SoC | `qcom,canoep` | `0x1010295 0x20000` | Alt / v2 | `0x0 0x0` | 否 |
| 7 | `07_dtb_536275.dtb` | 536,275 | CanoeP Alt. Thermal Profile SoC | `qcom,canoep` | `0x1010295 0x10000` | Alt / v1 | `0x0 0x0` | 否 |
| 8 | `08_dtb_576448.dtb` | 576,448 | CanoeP v2 SoC | `qcom,canoep` | `0x295 0x20000` | normal / v2 | `0x0 0x0` | 否 |
| 9 | `09_dtb_571031.dtb` | 571,031 | CanoeP SoC | `qcom,canoep` | `0x295 0x10000` | normal / v1 | `0x0 0x0` | 否 |
| 10 | `10_dtb_508061.dtb` | 508,061 | Whale SoC | `qcom,whale` | `0x2d2 0x30000` | normal | `0x0 0x0` | 否 |
| 11 | `11_dtb_503332.dtb` | 503,332 | WhaleP SoC | `qcom,whalep` | `0x2d3 0x30000` | normal | `0x0 0x0` | 否 |

运行时刻：`ro.boot.dtb_idx = 2`、`hw-revision = 20000`
（来源 `deliverables/gstack/_work/device-pixelos/dump/getprop-all.txt:987`、
`docs/fastboot-getvar-all.txt:8`）。

## 板级 overlay（`dtbo.img` 的 2 个 entry）

| idx | 文件 | 字节 | fragments | `qcom,msm-id` 集合（id / rev，十六进制） | 运行时 |
|---|---|---|---|---|---|
| 0 | `00.dtbo` | 141,842 | 45 | `0x2d3/0x30000`, `0x2d2/0x30000`, `0x2e7/0x20000`, `0x2e7/0x10000`（Whale / WhaleP / CanoeP-SG） | 否 |
| **1** | **`01.dtbo`** | **1,134,915** | **145** | `0x295`、`0x294`、`0x1000294`、`0x1000295` 的各 rev（Canoe / CanoeP） | **是** |

运行时刻：`ro.boot.dtbo_idx = 1`（同 dump `:988`）。

## 三条不能踩的坑

1. **`qcom,board-id` 不能当区分键。** 12 棵 base 全是 `<0x0 0x0>`（通配），`qcom,pmic-id` 根本不存在。
   写「按 board-id 选树」的逻辑在 canoe 的 4 棵之间是彻底歧义的。
2. **`qcom,msm-id` 也不是唯一依据。** 同一 SoC + 同 rev 仍有「正常 / Alt. Thermal Profile」两个变体
   （差 `| 0x01000000`），从 msm-id 反推不出设备实际走哪条。**运行时的 `dtb_idx` / `dtbo_idx` 才是**。
3. **`fdtoverlay` 能叠加成功不能当判据。** 两个 overlay 的 fragment 全是 `target = <0xffffffff>` +
   `__fixups__` 符号引用，不绑定具体 base；`00.dtbo`、`01.dtbo` 叠到 `00` / `02` / `03` 上都会「成功」。
   区分只能靠 overlay 根节点的 `qcom,msm-id` 集合是否包含 base 的 msm-id。

## 复现

```bash
python3 scripts/dttool.py manifest original/manifest.tsv \
    stock-a17=/root/work/dt-extract/stock/vendor_boot.img \
    stock-a17=/root/work/dt-extract/stock/dtbo.img
python3 scripts/dttool.py root original/base-parts/02_dtb_581424.dtb   # 看 / 节点全部属性
```
