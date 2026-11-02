# pandora 设备树重建报告

小米 17 Pro（pandora / canoe / SM8850）设备树从原厂固件提取、反编译、重建并逐字节校验的完整记录。
本文所有数字都来自仓库内脚本的实际输出（`make extract` / `make dtb` / `make merge` / `make verify`），
不是推算值。

- 复核命令：`make extract && make verify`
- 校验工具链：`dtc 1.7.0`、`fdtoverlay`、`python3`（仅标准库）

## 1. 结论摘要

| 项 | 结果 |
|---|---|
| 原厂 OTA 解包 | `dtbo` / `vendor_boot` 两分区，payload manifest sha256 双 PASS |
| 自行解包 vs 既有副本 | 逐字节一致（`cmp` 通过） |
| 拆出基础树 | 12 棵（`vendor_boot` dtb 段 6,557,139 字节） |
| 拆出 board overlay | 2 个 entry（141,842 + 1,134,915 字节） |
| base 树重建 | 节点/属性/路径/属性值 全部一致 |
| overlay 重建 | 结构一致；entry[0] 逐字节复现，entry[1] 序列化多 11 字节 |
| 合并树重建 | 与 `fdtoverlay` 真实合并结果完全一致（5,588 节点 / 34,152 属性） |
| dtbo.img 重建 | 头部与 2 个 entry 的 id/rev/custom/size/offset 全一致；entry[0] 逐字节复现 |
| 载荷 md5（前 1,276,853 B） | 原厂/PixelOS/LOS 三份都是 `a4b9b5f1455889044b11c86f1aff0fe7`；重建为 `06d069185fef5d0182d9ac2375edf6ab`（差 11 字节，见 8.2） |
| 三来源 dtbo | 原厂 A17 / PixelOS / LOS 的 dtbo 内容逐字节相同 |
| `make verify` | PASS 7 / FAIL 0 |

**本次发现并修复的实质缺陷**：旧流程的「校验」只比 `model` 与 `compatible` 四个字符串，因此没有发现
dts 里 **135 处属性值被 dtc 的字符串转义歧义改义**（详见第 8 节）。修复后重建树与原厂二进制在
`/` 节点、全树属性级都完全一致。

## 2. 解包来源与校验

| 来源 | 文件 | 字节 | sha256 |
|---|---|---|---|
| 原厂 OTA | `pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip` | 9,171,726,548 | `c5808a856410f0188556911450beaa5ac818e6130e0afd007a2b8cb5a6792ce7` |
| → `dtbo` | 23,068,672 | `751f3ed7c8e22ef2de28ce1b1628f3bd5cea03a09b0070a477a5098e1b2dd09c` |
| → `vendor_boot` | 100,663,296 | `b30b55dbe20b2b39fce8d2bf53e27352227c337d05af7fd681fb7968da0b1a4a` |
| PixelOS | `PixelOS_pandora-17.0-20261102/Fastboot_PixelOS_pandora-17.0-20261102-0424.zip` | 6,699,636,957 | — |
| → `dtbo`（包内） | 33,554,432 | `5aaabafd496185c70ae98f7cb9696c9220f7879036c0a7c5fb8a11017a7e3756` |
| → `dtbo`（同目录散装件） | 33,554,432 | `53094a7e7b9438282ebeff71ac704a12f96cdb9be2f203e98a3425dc5e7158b0` |
| → `vendor_boot` | 100,663,296 | `236f7939db0257fdda13ebd004c17b54caee8b98d7caa276922203308c7824f0` |
| LOS 构建产物 | `/root/work/gstack/los_dtbo.img` | 23,068,672 | `5688f25aa58fcb5239ee3103ac241cc2b3e4d9b3de98492dfa4f387be2848dc1` |

- `payload_dump.py … dtbo vendor_boot --verify` 输出 `verify summary: 2 ok, 0 failed`，即解出的两个分区
  与 payload manifest 里的 `new_partition_info.hash` 一致。
- 自己解出的 `dtbo.img` / `vendor_boot.img` 与既有副本 `/d/WSL/out/pandora/stock-a17/*` **逐字节相同**
  （`cmp` 通过），说明解包链路没有引入偏差。
- PixelOS 的 `dtbo.img` 包内件与散装件 sha256 不同，但前 1,276,853 字节（整个 dt_table 区）完全相同，
  差异只落在分区尾部 AVB 结构上（见 8.3）。

## 3. 两个镜像的内部结构

### 3.1 vendor_boot（header v4）

| 字段 | 值 |
|---|---|
| magic | `VNDRBOOT` |
| header_version / page_size | 4 / 4096 |
| vendor_ramdisk_size | 22,173,394（PixelOS: 22,172,655） |
| dtb section offset | 22,179,840（= align_up(4096 + vendor_ramdisk_size, 4096)） |
| dtb_size | 6,557,139 |
| dtb_addr | 0x1F00000 |
| vendor_ramdisk_table | 108 字节 × 1 |
| bootconfig_size | 270 |

dtb 段是 12 棵 FDT 的紧凑拼接，按 `magic + totalsize` 切开后拼接可 100% 还原原始字节：

```
00 581542  01 576027  02 581424  03 576007  04 509818  05 501152
06 536022  07 536275  08 576448  09 571031  10 508061  11 503332
```

### 3.2 dtbo.img（Android dt_table v0）

```
magic=0xd7b7ab1e  total_size=1,276,853  hdr_size=32  entry_size=32
entry_count=2     entries_offset=32     page_size=4096  version=0
[0] offset=96       size=141,842    id=0 rev=0 custom=0,0,0,0
[1] offset=141,938  size=1,134,915  id=0 rev=0 custom=0,0,0,0
```

注意布局是**紧凑**的：首个 entry 直接跟在 32 + 2×32 = 96 字节之后，没有按 `page_size` 对齐，
`total_size` 也不是页的整数倍（原厂分区镜像 23 MB 是分区填充 + AVB，不是 dt_table 本身）。
旧的打包器按页对齐，`dtbo.img` 布局与原厂对不上，本次给 `mkdtimage.py` 加了 `--packed` 与 `--meta`。

## 4. 为什么选 02 号基础树 / 01 号 overlay

这两个选择**不是推断，是设备侧 dump 的直接结果**：

| 证据 | 值 | 出处 |
|---|---|---|
| `ro.boot.dtb_idx` | `2` | `deliverables/gstack/_work/device-pixelos/dump/getprop-all.txt:987` |
| `ro.boot.dtbo_idx` | `1` | 同上 `:988` |
| `hw-revision`（fastboot getvar） | `20000` | `docs/fastboot-getvar-all.txt:8` |
| `ro.media.xml_variant.codecs` 等三处 | 指向 `_canoe_v2` | 同一 getprop dump |

12 棵 base + 2 个 overlay 的完整静态属性表见 [`dtb-selection-matrix.md`](dtb-selection-matrix.md)
（含 `msm_id` / variant / `board_id` / 运行时列，并标注了「board-id 不能当区分键」等三个坑）。

- `dtb_idx=2` 是 **dtb section 内的 0 基索引**，与 `original/base-parts/02_*` 的编号同源：
  已核对 dtb section 起点 `0x1527000`、12 棵首尾相接无填充、总长 6,557,139 B，按序 md5 与
  `base-parts/00..11` 一一对应——**文件名前缀就是 section 顺序**，不是约定俗成。
- `dtbo_idx=1` 直接指向 `01.dtbo`（1,134,915 B，145 fragments）。
- entry 的 `id/rev/custom[0..3]` **两个 entry 全是 0**，靠元数据无法区分，只能靠 overlay 根节点的
  `qcom,msm-id` 集合：entry0 = {`0x2d2/0x30000`, `0x2d3/0x30000`, `0x2e7/0x20000`, `0x2e7/0x10000`}
  （Whale / WhaleP / CanoeP-SG），entry1 = {`0x294`, `0x295`, `0x1000294`, `0x1000295`} 的各 rev。
  pandora 是 `0x294`，**entry0 根本匹配不上**。

交叉验证（不作为主证据，只用于自检）：

| # | qcom,msm-id | model（去掉 Qualcomm 前缀） | 合并 01.dtbo |
|---|---|---|---|
| 00 | `0x1000294 0x20000` | Canoe Alt. Thermal Profile v2 SoC | OK（1,651,454 B） |
| 01 | `0x1000294 0x10000` | Canoe Alt. Thermal Profile SoC | OK（1,645,939 B） |
| **02** | **`0x294 0x20000`** | **Canoe v2 SoC** | **OK（1,651,336 B）** |
| 03 | `0x294 0x10000` | Canoe SoC | OK（1,645,919 B） |
| 04 / 05 | `0x2e7` | CanoeP SG v2 / SoC | FDT_ERR_NOTFOUND |
| 06 / 07 | `0x1010295` | CanoeP Alt. Thermal Profile | FDT_ERR_NOTFOUND |
| 08 / 09 | `0x295` | CanoeP v2 / SoC | OK（1,646,360 / 1,640,943 B） |
| 10 / 11 | `0x2d2` / `0x2d3` | Whale / WhaleP | FDT_ERR_NOTFOUND |

> **注意：`fdtoverlay` 的成败不能当判据。** 两个 overlay 的 fragment 全是 `target = <0xffffffff>` +
> `__fixups__` 符号引用，不绑定具体 base，`00.dtbo`/`01.dtbo` 叠到 02/03/00 上都能「成功」。
> 上表的 OK/FAIL 只能说明「这棵 base 里存在 overlay 引用的那些符号」，不能说明选对了。

`02` 与 `03` 选的也不只是名字：v2 的 `chosen/bootargs` 有 `disable_dma32=on`、没有
`arm64.nosme`/`swiotlb=0`/`initcall_blacklist=ufshcd_core_init`，`/soc/clock-controller@20f0000`
是 `qcom,canoe-videocc-v2`（03 是 `qcom,canoe-videocc`）。`02` 与 `00`（同为 v2）合并后整棵树
5,588 节点完全一致，只有 4 处属性不同（`/model`、`/qcom,msm-id`、`/chosen:bootargs`、videocc 的
`compatible`），也印证了「Alt. Thermal Profile」在 DT 层面几乎收敛。

## 4b. 三条硬约束（写死在脚本默认值里）

1. **base 必须保留根节点 `qcom,msm-id = <0x294 0x20000>`**——写错 ABL 直接不启动，所以 `make merge`
   的 `BASE` 默认硬编码为 `original/base-parts/02_dtb_581424.dtb`，不做「自动挑第一棵 canoe」那种启发式。
2. **dtbo.img 必须 2 个 entry，顺序为 `[whale/canoep-SG 组(00), canoe/canoep 组(01)]`**，不能反——
   `ro.boot.dtbo_idx=1` 依赖这个下标语义。
3. **overlay 必须按 `qcom,msm-id` 集合选**，不能按 fragment 数或体积选。

## 5. 合并方式与结构对账

`make merge` 用上游工具做真实合并，不再把「手写合并 dts」当成唯一真相：

```bash
fdtoverlay -i original/base-parts/02_dtb_581424.dtb -o build/runtime.dtb original/dtbo-parts/01.dtbo
dtc -I dtb -O dts -o build/runtime.dts build/runtime.dtb
```

对账口径比旧版严格得多：**节点数 + 属性数 + 排序后的节点路径集合 + 每个节点每个属性的原始字节**。

```
A = build/xiaomi-pandora.dtb  (1,650,827 字节)
B = build/runtime.dtb         (1,651,336 字节)
节点数   A=5588   B=5588   一致
属性数   A=34152  B=34152   一致
节点路径集合  A∪B=5588，仅 A 有 0，仅 B 有 0
属性名差异 0 处，属性值差异 0 处
结果: PASS 结构完全一致
```

（节点统计含根节点 `/`；旧 README 里的 50,917 是 `dtc -O dts` 的行数，不是节点数，两者不能混用。）

## 6. 产物清单

| 文件 | 字节 | 与原厂的差异 |
|---|---|---|
| `build/canoe-base.dtb` | 581,454 | 原厂 581,424，+30（字符串表打包差异） |
| `build/overlays/board-pandora-alt.dtbo` | 141,842 | **与原厂 entry[0] 逐字节相同**（sha256 `fe9c482a96ca65c7…`） |
| `build/overlays/board-pandora.dtbo` | 1,134,926 | 原厂 1,134,915，+11 |
| `build/xiaomi-pandora.dtb` | 1,650,827 | 与真实合并树仅序列化差异，属性级 0 差异 |
| `build/runtime.dtb` | 1,651,336 | `fdtoverlay` 合并原厂 base+overlay 的结果 |
| `build/runtime.dts` | 3,219,810 | 上者反编译，供阅读 |
| `build/dtbo.img` | 1,276,864 | 原厂 1,276,853，+11（全部来自 entry[1]） |

`extracted/`（38 MB，已 gitignore）内含三来源的 dtb/dtbo/反编译 dts；`original/manifest.tsv`（入库）
是 30 行清单：`source / part / index / offset / size / id / rev / custom0..3 / model / compatible / sha256`。

## 7. 校验矩阵

`make verify` 的实际输出汇总（PASS/FAIL 由脚本判定，任一 FAIL 则退出码非 0）：

| 校验 | 对象 | 结果 |
|---|---|---|
| 结构对账 | `runtime.dtb` vs `xiaomi-pandora.dtb`（5,588 节点 / 34,152 属性 / 路径集合 / 全部属性值） | **PASS** |
| (a1) 根节点 | 原厂 base `02_dtb_581424` vs `canoe-base.dtb`（7 个属性） | **PASS 7 / FAIL 0** |
| (a2) 根节点 | 原厂 `01.dtbo` vs `board-pandora.dtbo`（5 个属性） | **PASS 5 / FAIL 0** |
| (a3) 根节点 | `runtime.dtb` vs `xiaomi-pandora.dtb`（7 个属性） | **PASS 7 / FAIL 0** |
| (b1) dtbo.img | 原厂 A17（23,068,672 B）vs 重建 | **PASS 23 / SIZE·BYTES 2 / FAIL 0** |
| (b2) dtbo.img | PixelOS（33,554,432 B）vs 重建 | **PASS 23 / SIZE·BYTES 2 / FAIL 0** |
| (b) 载荷 md5 | 前 1,276,853 B：原厂 `a4b9b5f1…` vs 重建 `06d06918…` | **BYTES**（结构/语义/元数据全等，仅序列化不同） |
| (c) 三来源 | stock-a17 / pixelos / los 的 dtbo entry | **PASS**（全部 entry 逐字节相同） |

> `SIZE` / `BYTES` 不是"网开一面"：它们的判定条件是「`size_dt_struct` 相等 + token 流语义相等 +
> entry 元数据全等」，缺一即 `FAIL`。它证明的是**结构语义全等、只有序列化细节不同**，
> 而不是逐字节一致——逐字节一致从来不是本任务的验收项。

根节点属性是**枚举 `union` 全集**逐个比的，不是固定比四个字段：

- base：`model`、`compatible`、`qcom,msm-id`、`interrupt-parent`、`#address-cells`、`#size-cells`、`qcom,board-id`
- overlay：`model`、`compatible`、`qcom,msm-id`、`qcom,board-id`、`xiaomi,miboard-id`
- 合并树：与 base 相同的 7 个（`compatible` 由 overlay 覆盖）

dtbo.img 逐项对照覆盖：`magic`、`version`、`page_size`、`entry_count`、`hdr_size`、`entry_size`、
`entries_offset`，以及每个 entry 的 `id`、`rev`、`custom[0..3]`、`dtb_size`、`offset`。

## 8. 已知差异，以及为什么不影响运行时

### 8.1 属性值 136 处被 dtc 转义歧义改义（**已修复**）

旧 dts 里大量出现这种写法：

```dts
jeita_para = "-65535\0-10\00\02\00\04480\060\0null\0…";
```

原值是**字符串列表** `"0", "2", "0", "4480", "60"`（NUL 分隔）。`dtc -O dts` 把 NUL 渲染成 `\0`
再把后续字符原样输出，于是 `\0` 紧跟数字时，回读被当成两位八进制 —— `\00` 吃成 0x00、`\02` 吃成
0x02，一个字节被吞掉，值随之改义。重建后：

- 合并树 135 处属性值与设备实际树不同（`jeita_para`、`adapter_para*` 等充电曲线参数）；
- overlay 134 处、base 2 处。

这类属性不是给人看的注释，`jeita_para` 直接参与电池 JEITA 充放电策略。本次把 `dts/` 中这些值改为
**逗号分隔字符串列表**（字节等价）或 u32 cell，共改写：

| 文件 | 改写行数 |
|---|---|
| `dts/xiaomi-pandora.dts` | 135 |
| `dts/overlays/board-pandora-overlay.dts` | 134 |
| `dts/xiaomi-pandora-common.dtsi` | 2 |

修复后三棵树的属性值差异全部归零。`extracted/` 里的反编译 dts 也走同一套 `normalize-dts` 处理，
所以 `make extract` 的产物本身是无损的。

### 8.2 二进制差异：语义 0 差异，字节差异来自「字符串表打包 + 对齐填充」

分两层看。

**语义层（0 差异）**：按 FDT token 流（NODE / PROP / END，nameoff 换成真实属性名）解析，`01.dtbo` 与
重建产物 **23,026 个 token、18,801 个属性全部一致**；`dttool.py cmp` 的 路径→属性→原始字节 对比
同样是 0 差异。把两边按同一 token 序列、用一张统一的字符串表**重新序列化**，结构块逐字节相同：

```
01.dtbo   归一化序列化后 同=True (1087088/1087088)
02_dtb    归一化序列化后 同=True (528068/528068)
```

**字节层（两处差异）**：结构块差异 = ① `nameoff` 字段指向（两版字符串表布局不同，内容等价）
+ ② 原厂对齐填充里的脏数据（entry[1] 4,912 B 非零、base `02` 1,189 B 非零）；后者 dtc 1.7 一律写 `0x00`。

| 对象 | `size_dt_struct` | struct 是否逐字节同 | `size_dt_strings` | `totalsize` |
|---|---|---|---|---|
| base `02` | 528,068 / 528,068 | 否（nameoff 指向 + 1,189 B 脏填充） | 53,300 → 53,330（+30） | 581,424 → 581,454 |
| entry[1] `01.dtbo` | 1,087,088 / 1,087,088 | 否（同上，5,118 B） | 47,771 → 47,782（+11） | 1,134,915 → 1,134,926 |
| entry[0] `00.dtbo` | 122,364 / 122,364 | **是**（`ab87936b50622e8c…`） | 19,422 → 19,422（+0） | 141,842 → 141,842 |

> 口径说明：「1,189 / 5,118」是**整个 struct 块里「原厂非 0 且重建为 0」的位置数**，含 `nameoff`
> 恰好为 0 的那几项；只算对齐填充则是 base **1,156**、entry[1] **4,912**、entry[0] **0**。
> 两个口径都要给，否则单看任一个都会被复算出不同结果。

三个对象的 struct 块**尺寸全等**，`00.dtbo` 连内容都全等（整文件 sha256 `fe9c482a96ca65c7…`）。
`off_dt_struct` / `off_dt_strings` / `off_mem_rsvmap` 也都相同（56 / 1,087,144 / 40）。

(a) **字符串表 +11 字节**：dtc 1.7 会把属性名指向已有条目的后缀（实测 `/__fixups__:tlmm` 的 nameoff
指向 `lpi_tlmm` 尾部），厂商当年那版 dtc 在 `tlmm` / `mux` / `swr_haptics` 三个短名上的取舍不同。

(b) **属性值末尾的对齐填充**：厂商那版在 4 字节对齐的填充里留了**脏数据**，dtc 1.7 一律写 `0x00`。

| 文件 | 属性数 | 填充 `0x00` | 填充 `0x30` | 其他非零 | 填充合计 |
|---|---|---|---|---|---|
| `00.dtbo`（原厂） | 3,222 | 1,574 | 0 | 0 | 1,574 |
| `board-pandora-alt.dtbo`（重建） | 3,222 | 1,574 | 0 | 0 | 1,574 |
| `01.dtbo`（原厂） | 18,801 | 4,279 | 42 | **4,870** | 9,191 |
| `board-pandora.dtbo`（重建） | 18,801 | 9,191 | 0 | 0 | 9,191 |

抽样可见脏填充是缓冲区残渣而非结构化数据：`pins = "gpio9"` 后面跟 `68 30`（`h0`）、`gpio2` 后跟
`2d 65`（`-e`）、`function = "paired"` 后跟 `30`（`'0'`）——零填充的打包器产不出这种内容。

这解释了为什么**两个 entry 一个能逐字节复现、一个不能**：`00.dtbo` 的填充本来就是全零，所以重编译
后整文件相等；`01.dtbo` 有 4,912 个非零脏填充，任何重编译都不可能复现。

这 4,912 字节落在属性值之后、到下一个 4 字节边界之间的对齐间隙里，**不属于任何属性的取值**；
FDT 解析器按 4 字节对齐直接跳过，ABL 与内核都不会读它们，因此不影响解析结果与运行时行为。
（但同样不能把重建产物说成「与原厂逐字节相同」。）

**`00.dtbo` 与 `01.dtbo` 的上游产物不是同一条构建链路**，有三条独立证据：

1. **`fragment@N` 编号**：`00.dtbo` 是连续的 `0..44`（45 个，0 空洞）；`01.dtbo` 是 `0..245` 里挑出的
   145 个，**101 个空洞**——`0..45` 段完整，从 46 起偶数几乎全删（46/48/…/244），另删了 85、95，
   只留 86/208/228 三个偶数。**dtc 不会重编号节点**，说明 `01.dtbo` 的树在序列化前被裁剪过
   fragment，而 `00.dtbo` 没有。
2. **对齐填充**：`00.dtbo` 1,574 B 全零；`01.dtbo` 9,191 B 里 4,912 B 未初始化残留。
3. **字符串表 interning**：`00.dtbo` 与 dtc 1.7 的输出**逐字节相同**（19,422 B 全等）；`01.dtbo` 的短名
   后缀复用取舍相反（+11 B）。

两份的 FDT 头字段完全相同（`version=17`、`last_comp_version=16`、`off_mem_rsvmap=40`、
`off_dt_struct=56`、结构块与字符串表之间无间隙、文件末尾无填充），所以不是「不同 FDT 格式」这种
粗暴差异，而是同一代工具下的不同构建链路。

> **边界**：以上只证明「两个 `.dtbo` 的上游产物不同链路」。`dtbo.img` 本身是**一次** `mkdtboimg`
> 打包出来的——`entry0.offset 0x60 + entry0.size 141,842 = 0x22A72 = entry1.offset`，entry 之间零
> 填充，`total_size` 恰为最后一段结束处。不要写成「dtbo.img 由两次构建拼装」。
> 「分属不同团队/不同 target」仍属推测，无直接证据。

因此 `dtbo.img` 载荷为 1,276,864 B（原厂 1,276,853 B，+11），两个 entry 的 offset 仍是
`96` / `141,938`（entry[0] 逐字节复现）。

**校验门禁不是 md5**：md5 相等意味着「连厂商那版 dtc 的字符串表打包顺序都复现了」，而那不是本任务
要还原的东西。`verify-img` 的硬判据是三条**同时**满足：① 每个 entry 的 `size_dt_struct` 与原厂相等；
② 反编译出的树语义 diff 为 0；③ entry 元数据（id/rev/custom/dtb_size/offset）全等。三条全过 → 输出
`BYTES`（打印两个 md5，不计失败）；任一条不过 → `FAIL`。同时把 `size_dt_strings` 的差值（+30 / +11 /
+0）作为 `INFO` 打出来，一眼能看到差在哪、差多少。

> 要做到载荷 md5 完全相等（`a4b9b5f1…`）只能换厂商同版本 dtc，或用原厂字符串表+填充做二进制后处理
>（那就不是重建了）。这是**唯一**未能字节级复现的环节。

### 8.3 22 MiB / 32 MiB 镜像的尾部 AVB 结构

三份 dtbo 镜像的前 1,276,853 字节（`total_size`，即头 + 两个 entry 的载荷）**逐字节相同**，
md5 都是 `a4b9b5f1455889044b11c86f1aff0fe7`。其后是 `avbtool add_hash_footer` 的东西：

| 镜像 | 文件大小 | 与 stock 的差异字节数 | 首个差异位置 |
|---|---|---|---|
| stock-a17 | 23,068,672（= 22 MiB） | — | — |
| los | 23,068,672 | 119 | 1,278,023 |
| pixelos（散装） | 33,554,432（= 32 MiB） | 257 | 1,278,023 |

- vbmeta 结构在 `0x138000..0x138640`（640 B = 256 B 头 + 384 B aux），`AVB0` 魔数；`auth_block_size=0`
  （无签名）、`aux_block_size=0x180`，hash descriptor 的 **salt 是随机值**，所以每次盖章 digest 都不同。
  区间内非零字节：stock **236** / pixelos **254** / los **227**。
- AVB footer 独立位于文件末尾 64 B（`AVBf`，声明 `orig_size=1,276,853`、`vbmeta_off=0x138000`、
  `vbmeta_size=640`，三份完全相同），其中 12 B 非零。
- 因此表（1,276,853 B）之后到文件尾的全部非零字节只有：stock **248**、pixelos **266**、los **239**
  （= vbmeta 非零 + footer 非零），其余都是 0 填充。

所以「三份 dtbo 不同」只体现在签名与分区尺寸上，**设备树内容三份完全一致**。
`verify-img` 因此只比前 `total_size` 字节，不比整文件 md5，否则会把 AVB salt 差异算成失败。

另外注意：原厂那份 22 MiB 是 **payload 抽取的结果**，而 dtbo 分区本身是 `0x2000000` = 32 MiB
（fastboot 报 `dtbo_a = 0x2000000`），PixelOS 那份才是整分区 dump。`build/dtbo.img` 只有 1.2 MB，
要产出可 `dd` 回分区的镜像需要自行补零到 32 MiB（fastboot flash 会自动补齐，但 dd 不会）。

### 8.4 LOS 的 dtbo 是「原厂载荷 + 重新盖 AVB 章」

`los_dtbo.img` 的 dt_table 头、两个 entry 的元数据、以及前 1,276,853 字节载荷与原厂**完全相同**
（md5 `a4b9b5f1…`），两个 `.dtbo` 也逐字节相等；差别只有 vbmeta 块 640 字节左右（salt 重随机、
`auth_block_size=0` 无签名）。也就是说 LOS 侧的 dtbo **不是从 dts 重建的**，而是
「同一份原厂载荷 + 重跑 `avbtool add_hash_footer`」——典型的 `BOARD_PREBUILT_DTBOIMAGE` 用法。
如果 LOS 构建流程预期「自己编译过 dtbo」，这里值得复核。

### 8.5 没做到的

- 没有设备侧 `/proc/device-tree` 导出可对照，所以「02 号树就是本机在跑的那棵」是选择器 + SoC 版本
  的交叉推断，不是实测。
- `extracted/` 与 `original/manifest.tsv` 依赖 9 GB 原厂 OTA；仓库不存 OTA，新克隆必须先跑
  `make extract` 才能 `make verify`（`original/base-parts/*.dtb` 已从 gitignore 豁免入库，6.5 MB）。

## 9. 复现

```bash
# 1) 解包（需要原厂 OTA 与 PixelOS fastboot 包）
make extract STOCK_OTA=/path/to/pandora-ota_full-….zip \
             PIXELOS_ZIP=/path/to/Fastboot_PixelOS_….zip

# 2) 编译 + 合并 + 深度校验
make verify

# 只做合并对账
make merge BASE=original/base-parts/02_dtb_581424.dtb OVERLAY=original/dtbo-parts/01.dtbo
```

Git Bash 无 `dtc`/`fdtoverlay` 时会由 `scripts/in-wsl.sh` 自动转发到 WSL 执行（当前环境即如此）。
中间镜像默认解到 `/root/work/dt-extract`，仓库内只留 38 MB 的 `extracted/`。
