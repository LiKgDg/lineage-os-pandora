# 实验矩阵 v4：pandora / LOS24 启动故障（三条离线取证结论落地后收口）

**评估人**：gstack-qa-lead（QA 与发布）
**基线**：`_member/tessa-test-strategy.md`（v2）+ `tessa-test-strategy-v3-addendum.md`（v3 补遗 D1–D7）
**本次输入**：结论 A（fstab 双向比对完成）、结论 B（`CONFIG_PSTORE_RAM=y`）、结论 C（`-w` 从未碰 userdata）
**性质**：v4 是**收口版**。v3 的三条待决（D3 / D5 / D6）全部落地，矩阵从"待补实验"变为"可执行清单"。

---

## TL;DR

1. v3 三条待收口全部关闭：**D3 关闭**（离线比对已做完且无差异）、**D5 裁定为"报告对、build-notes 错"**、**D6 升为矩阵第 0 步 G0**（症状归属门禁）。
2. 删 3 条：**E1b 取消**（立论被 A 杀 + 两成分已被 C 覆盖）、**E1a 维持取消**、**X2 取消**（现场灭失，且 metadata 被擦 3 次后 blob mtime 必已重建，读数零信息）。新增 2 条：**E1c（真 format userdata）**、**A1（`atgc` 单 token 消融）**。
3. 重定性 1 条：**pstore/pmsg 取证链**——通道确实存在（B），且 `PSTORE_CONSOLE=y` 意味着内核 printk 持续落盘，**这是当前唯一不依赖 /data 可解密、又能带回"卡住瞬间"的通道**；但"读数侧"（TWRP 的内核）是否注册了 ramoops 本身要先自检——不自检就记"pstore 为空"，那是无效态，不是阴性。
4. 仍需刷机，但目的变了：不再是"验证 /data"，而是**打通一条能带回日志的通道**——这是唯一能补上 VNDK / VINTF / HAL 三族零覆盖的手段，而这三族至今无任何主动实验。
5. 一句话判断：**下一步是先取回 ramoops 里那几百行内核日志；在拿到之前，不要做任何 wipe。**

---

## 1 证据基线（先把三条结论变成可复核的事实）

### 1.1 结论 A —— 我独立复核，成立；两处表述需更正

我没有沿用口头结论，而是从本机已有的两侧 ramdisk 重新提取并逐行比对。**可复现**：

```bash
cd deliverables/gstack/_work && python extract_fstab.py
# los_vendor_ramdisk.cpio   -> fstab-qcom-los.txt    8928 bytes  sha256=6a6f28e5...
# stock_vendor_ramdisk.cpio -> fstab-qcom-stock.txt 13814 bytes  sha256=391d5143...
```

| 项 | LOS | stock |
|---|---|---|
| `first_stage_ramdisk/fstab.qcom` 大小 | 8928 B | 13814 B |
| sha256 | `6a6f28e52f571132bbd66a60ff89e12a88557f662bad0ddba66c6f6635b55a09` | `391d51430df0cb45a916e5508ebed51fade8b13d9674d7d04ee438031b382f1b` |
| 非注释行数 | 34 | 62 |
| `/data` 行含 `formattable` | **是** | **是** |
| `/metadata` 行文件系统 | **f2fs**（`wait,check,formattable,first_stage_mount`） | **f2fs**（逐字相同） |
| 两侧共有但内容不同的行 | **只有 `/data` 一行**，差异是 LOS 多 `,atgc`（480 B vs 475 B） | — |
| stock 独有行 | 28 行 / 26 个挂载点（`mi_ext` 占 ext4+erofs 两行，另含 `/mnt/rescue`、`/mnt/vendor/vm-persist`） | — |
| 其中带 `nofail` | 27 行 | — |

**更正 1（表述精度）**：「stock 多出的整段全部带 `nofail`」不精确。有 1 行不带：
`/dev/block/bootdevice/by-name/vm-persist /mnt/vendor/vm-persist ext4 noatime,nosuid,nodev,barrier=1 wait`（只有 `wait`，无 `check`、无 `nofail`）。
**方向不变**——LOS 少挂载一个分区不会导致挂载失败，只可能少一个挂载点；但执行者若照"全部 nofail"去推理，会误以为这 28 行都有兜底。台账须按上表写。

**更正 2（结论加强，不是削弱）**：`atgc` 是**内核能识别的 f2fs 挂载 token**。在内核映像字符串表中有独立的 `\0atgc\0`，上下文紧邻 `prjjquota=%s`、`data_flush`、`noinline_xattr`（即 f2fs 的 mount option token 表），故不会因未知选项返回 EINVAL。
因此 A 的结论比原表述更强：**fstab 侧不存在任何可致挂载失败的差异**——不只是 `formattable` 对称，连唯一的多余 token 也是合法的。

**A 杀掉的是什么**：v3 D2 的机制「stock 有 `formattable` 就重建 / LOS 没有就卡住」**不成立**（两侧都有，且逐字相同）。该机制死亡，**零不可逆消耗**。
**A 留下的是什么**：`atgc` 是唯一残留的 fstab 侧变量。它是合法 token，但"合法 token"不等于"运行时前置条件满足"（f2fs 的 ATGC 依赖 section/segment 布局等，离线无法判定）。概率低，但这是 A 之后**唯一还能被 fstab 解释的失败路径**，故立项 A1（见 §6 #14）。

### 1.2 结论 B —— 我核了原文，成立

`deliverables/gstack/_work/los_kconfig.txt` 第 7236–7242 行：

```
CONFIG_PSTORE=y
CONFIG_PSTORE_DEFAULT_KMSG_BYTES=10240
CONFIG_PSTORE_COMPRESS=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
# CONFIG_PSTORE_BLK is not set
```

`build-notes §33`「TWRP 里 `/sys/fs/pstore` 为空（内核未配置 ramoops）」**是错的，撤销**。v3 D5 二选一裁定：**报告对，build-notes 错**。

v4 在 B 之上补两条 B 没说的：

- **读数侧未验证**。ramoops 通道存在于 **LOS 的内核**；但读它的人是 **TWRP**，那是另一个内核 + 另一份 dtb。若 TWRP 的 dtb 不含 `ramoops-region` 保留内存节点，`/sys/fs/pstore` 会**天生为空**——此时"pstore 为空"是**观测失效**，与"内核没留记录"完全不同。这一步必须先自检（§4）。
- **`CONFIG_PSTORE_BLK is not set`** → 没有块设备后端，ramoops 是唯一后端，**掉电即失**。所以纪律不变且更硬：一律 `fastboot reboot` 收尾，禁止长按电源。

### 1.3 结论 C —— 成立，但**承重证据要换位**

结论不变：**userdata 从未被擦除或格式化**。但量纲论证（5.492 s 内处理 477.25 GiB 需 86.9 GiB/s）**不能当承重证据**——UFS 上的 erase 通常映射为 discard/unmap，接近瞬时，这个算术只能否定"逐字节写零式格式化"，不能否定"erase 指令本身"。

**承重证据换成三条日志结构事实**（都不依赖吞吐）：

1. 三份日志里 `-w` 段**只有一条** `Erasing 'metadata' OKAY [4.020s]`，没有任何 `Erasing 'userdata'` 行。fastboot 的 `-w` 对每个待处理分区都会打印一行 `Erasing '<name>'`。
2. `File system type raw not supported` 归属 **metadata**：同批 `getvar all` 显示 `partition-type:metadata:raw`、`partition-type:userdata:f2fs`。若 userdata 被处理，fastboot 会打印 `f2fs not supported` 而不是 `raw`。
3. fastboot 的 `-w` 输出是**每分区成对**（一行 erase + 紧跟一段 format 结果）；本日志里成对的只有 metadata 一组，且随后直接 `Finished`。

补充量纲（作为旁证，不作承重）：`partition-size:userdata: 0x77501FB000` = **477.25 GiB**；`metadata` = `0x4000000` = **64 MiB**。`current-slot:a`、`slot-count:2`、`unlocked:yes`、`security-patch-level:2026-02-01`（10-27 14:55，比刷机早 3 分钟，同一次会话）。

**C 的连带后果（v4 必须写明）**：
- `build-notes §31` 的排除项「data 加密不兼容 ← 刷前已 `-w` → 排除」**依据不成立，退回「未验证」**（不是"可疑"，是整条作废）。
- `§27`「清 data 后仍卡住」是**实验未执行（S0）**，不是阴性。
- **v3 D1 有一处说反了**：D1 说"E1b 的两个成分都已被执行过"。准确说法是——`erase metadata` 被执行过，`-w` 执行过，但**userdata 从未被格式化**。因此"干净 /data"这一臂**从未执行**。E1b 之所以该取消（§3），不是因为它测过了，而是因为它**测的不是这件事**。

---

## 2 被新证据杀掉 / 降级的条目清单

| # | 条目 | 因哪一句 | 新状态 |
|---|---|---|---|
| 1 | v3 D2 机制「LOS 无 `formattable` → 解不开不重建」 | A：两侧 userdata 行**都含 `formattable`**，逐字相同，唯一差异是 `,atgc` | **机制取消**（死亡，零成本） |
| 2 | v3 D3 离线 fstab flags 比对（原 P0 门禁） | A：已完成，产物见 §1.1 | **关闭**（转为已证实事实） |
| 3 | **E1b**（`erase metadata` + `-w`） | A：立论依据死亡；C：两个成分已被 10-27 那三次同一次操作覆盖 | **取消**（详见 §3） |
| 4 | E1a（TWRP format data） | v2 已取消；A 未给新理由，且 TWRP vold ≠ LOS vold | **维持取消** |
| 5 | `§31` 排除项「data 加密不兼容」 | C：`-w` 从未碰 userdata，排除依据不成立 | **退回「未验证」** |
| 6 | `§27`「清 data 后仍卡住」= 阴性先验 | C：实验未执行 | **改记 S0**（已执行但不可采信 → 实为未执行） |
| 7 | v2 §7 P0「TWRP 只读取证链（pstore→pmsg→tombstones→dropbox）」 | B：通道存在；但 `tombstones`/`dropbox` 在 `/data` 解不开时不可读，pstore 是唯一不依赖 /data 的通道 | **重写为单通道 + 前置自检**：D2（读数侧自检，P0）+ 判据表（§4）；tombstones/dropbox 移出 P0 |
| 8 | `build-notes §33`「内核未配置 ramoops」 | B：`CONFIG_PSTORE_RAM=y` | **错误，撤销** |
| 9 | `§33` 表 #5「first_stage fstab 错误 → 排除」 | A：从"脚本自报"升级为"工具逐行已验证" | **升级为已证实**（唯一被加强的一条） |
| 10 | v3 D5 ramoops 两说冲突 | B：已裁定 | **关闭** |
| 11 | **X2**（TWRP 读 key blob mtime） | v3 D4：现场已灭失；C：metadata 被擦 3 次，blob 必已重建，mtime 无判别力 | **取消** |
| 12 | v2 覆盖度标记「/data × E1a = ⊘」 | C：wipe 从未真正执行 → 该臂是**不覆盖**，不是"伪覆盖" | **改标 ○**，由 E1c 补 |
| 13 | v3 D6 症状归属（原列为"报告缺陷"） | 未被推翻，且是全部判读的前提 | **升级为矩阵第 0 步 G0** |
| 14 | v2 三态判定表 | 未被推翻 | **保留并扩为四态**（§7） |
| 15 | E0（静态先验） | v2 S3：静态结论不该占实验编号 | **移出实验表**，作为先验输入 |
| 16 | — | A 的副产物：`atgc` 是唯一残留 fstab 变量 | **新增 A1**（§6 #14） |
| 17 | — | C 的副产物：userdata 从未格式化 | **新增 E1c**（§6 #17） |

---

## 3 E1a / E1b 的最终处置

### 3.1 E1b：取消

**现在还剩什么理由做 E1b？——没有。** 逐条核过：

1. **立论依据已死**：E1b 原本唯一的机制主张是"两侧 fstab 不对称导致 LOS 不重建 /data"。A 证明两侧 userdata 行逐字相同、`formattable` 都在、`/metadata` 都是 f2fs。主张无立足点。
2. **操作已被覆盖**：E1b 定义为 `erase metadata` + `-w`。C 证明 `-w` 在本机的实际行为**就是** `erase metadata`；且 10-27 那三次已经各擦过一次。再执行一次是**空操作**，不产生新信息。
3. **它测的不是"干净 /data"**：`erase metadata` 只销毁密钥容器，userdata 的密文仍在 → 得到的是"孤儿密文"状态，而不是 clean slate。E1b 的成功/失败都无法区分"/data 内容有问题"与"/data 加密状态有问题"。

**取消后丢失什么信息**：**不丢**。它的两个成分已在台账里（10-27 三次），其机制主张已被 A 否证。

### 3.2 但「/data 侧」并没有被排除——这是 v4 最容易被误读的一点

C 证明 userdata **从未被格式化**；H1 的"清 data"是 S0；H2 的 `-w` 没碰 userdata。三条合起来：
**"在一个真正干净的 /data 上 LOS 能否启动"，本项目从未测过。** 该假设至今是**未验证**，不是"已排除"。

因此取消 E1b 之后，必须有一条替代臂，否则这个假设永久悬空。**这条是 E1c，不是 E1b。**

### 3.3 E1c：真 format userdata（新，取代 E1b）

| 项 | 内容 |
|---|---|
| 命令 | `fastboot erase metadata`（空操作，仅为台账完整）→ `fastboot erase userdata` → `fastboot reboot` |
| 为什么这样写 | `fastboot -w` 已被证明不格式化 userdata；`fastboot erase userdata` 是**语义确定**的原始分区擦除。擦除后首次挂载由 **LOS 自己的 fs_mgr/vold** 走 `formattable` 分支重建 f2fs —— 即"由被测系统自己执行 clean-slate"，比 TWRP 代劳（E1a）更接近真实路径，也避免引入 TWRP vold 这个第三方变量 |
| 能定案什么 | **通过**（能起）⇒ /data 侧假设成立，修复手段=刷机流程强制 wipe，与 version binding 无关<br>**失败**（仍卡 ≥15 min，症状同类）⇒ /data 侧假设被**第一次真正否证**，可从候选表移除，后续实验不必再考虑 wipe |
| 代价 | 不可逆（当前 /data 是 stock A17 可用的加密数据，擦掉即失）。但事故报告 §2 已认定原厂数据实质已失；恢复脚本 270 s 可用 → 边际损失低，仍需书面签收 |
| 恢复 | `restore_stock_full.sh`（须实测可用，不能只在纸面假设） |
| 前置 | G0 判症状为 A/B（userspace 域）；#1–#16 全部完成；签收 |

### 3.4 E1a：维持取消

TWRP 的 vold 与 LOS 的 vold 不是同一实现，format 语义不可控（可能只重建 /data 而保留旧 blob，**反而制造新的不匹配**）。E1c 用被测系统自身完成同一目标，语义更确定。E1a 不再立项。

---

## 4 pstore / pmsg 的重新定性

### 4.1 定性

- **通道存在**：`CONFIG_PSTORE_RAM=y` + `PSTORE_CONSOLE=y` + `PSTORE_PMSG=y` + 12/12 dtb 含 `ramoops` 节点。
- **两种落盘路径，判别力不同**：
  - `kmsg_dump()` 路径（panic / oops / emerg）—— 只有内核主动 panic/oops 才有；
  - **`PSTORE_CONSOLE=y` 的 console 路径 —— 内核 printk 被持续写入 ramoops**（环形覆盖，留下最后 N KB）。这意味着**即使静默复位、即使没 panic，只要内核打印过东西，ramoops 里就该有内容**。
- **结论**：`§31` 记的是"几秒后自动重启循环"，pstore 却为空。在 console 路径存在的前提下，"空"有两种解释：① 读数侧根本没注册 ramoops（**观测失效**，见 §4.2 第 0 步）；② 内核一行都没打印（未到内核）。**唯独不能解释成"内核没问题"**。
- 因此 B 的正确读法不是"pstore 没用"，而是：**pstore 是当前唯一可能带回"卡住瞬间内核在做什么"的通道，但必须先证明读数侧能读**。这使 #7 / #11 的优先级升到最前，而不是降级。

### 4.2 判据表（先看读数侧，再看内容）

**第 0 步：读数侧自检**（在 TWRP 内，10 秒）

```bash
ls -l /sys/fs/pstore/                                  # 有无目录/条目
dmesg | grep -i -e ramoops -e pstore                   # TWRP 内核是否注册 ramoops
ls /proc/device-tree/reserved-memory/ | grep -i ramoops # TWRP dtb 是否含保留内存节点
```

| 读数侧（TWRP） | LOS 侧症状 | pstore 有值 | pstore 为空 |
|---|---|---|---|
| **注册了 ramoops**（dmesg 有 ramoops，或 dt 有节点） | 任意 | **先看内容再判**：末几行是 `Kernel panic` / `Unable to handle` / `watchdog` / `BUG:` ⇒ 内核 panic/oops，**故障域=内核，全部 userspace 臂（E2/E2b/E7/E1c）当场无效**；只是普通启动日志戛然而止 ⇒ 内核在打印到该处后挂死或被静默复位，**卡点位置即故障位置**（这是本项目至今拿到的最有价值的一手证据） | 见下三行 |
| 注册了 ramoops | A 卡动画（动画逐帧，无回落） | — | **可疑**：console 路径应已留下内容。优先怀疑"内核一行没打"或读数时机/权限问题，不要直接记为阴性 |
| 注册了 ramoops | B 重启循环（数秒自重启） | — | 指向**静默复位**（PMIC/watchdog 无 panic 路径）或 console 记录未被写入；**不能推"内核没问题"** |
| 注册了 ramoops | C 卡第一屏 / 160 s 回落 fastboot | — | **弱证据**：指向 bootloader / early kernel（未到 pstore 注册）；须 D5（oem 日志）补强 |
| **未注册**（`/sys/fs/pstore` 不存在或恒空） | 任意 | — | **无效态**。不得记为阴性，不得据此推断任何事 |

**pmsg 的额外判据**：`CONFIG_PSTORE_PMSG=y` 只说明 `/dev/pmsg0` 存在，**默认没有写入者**。

```bash
ls -l /sys/fs/pstore/ | grep pmsg-ramoops    # 有且非空 ⇒ 用户态确实有写入者
```

- 出现 `pmsg-ramoops-0` 且非空 ⇒ pmsg 通道**可用**，是**唯一能跨复位带回 userspace 日志且不依赖 /data 可解密**的通道（`logd.logpersistd` 写 `/data` 的方案在 /data 解不开时无解，这是 X3 的原始缺陷）。
- 只有 `console-ramoops-0` 而无 pmsg ⇒ pmsg 无写入者，不要指望它。

---

## 5 G0：症状归属门禁（矩阵第 0 步）

**为什么它是第 0 步**：`§33` 记录"卡第一屏 160 s 回落 fastboot"——这已是 **bootloader/kernel 域**，此时矩阵里全部 userspace 臂（E2/E2b/E7/E1c）**即使执行也无效**。v3 D6 已指出四次复现是四种症状，且 18:26 之后无任何日志。**症状不定，矩阵不启动。**

### 5.1 离线部分（可立即做，零成本）

对**每一次复现**建一行台账，字段固定：

| 字段 | 取法 |
|---|---|
| 构建指纹 | 从 OTA zip 抽 `system/build.prop`：`ro.build.fingerprint` / `ro.build.version.release` / `ro.build.version.sdk` / `ro.build.version.security_patch`（工具：`_work/payload.py`） |
| 内核 banner | `strings _work/los_kernel.bin \| grep -m1 'Linux version'` → `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k` |
| vendor 世代 | `vendor/build.prop` 的 `release_or_codename`（A16=Baklava / A17） |
| 刷入分区清单 | `flash-log-*.txt`：7 分区（10-27）/ 13 分区（§31）/ 11 分区（§33） |
| 是否 wipe | 按 §1.3：**三次 `-w` 均未格式化 userdata**，一律记 `metadata-only` |
| 症状类别 | 现场记录（见 5.2），未记录者记"未归档" |

对账后应能回答：**"卡动画"到底只属于 A16 blobs 构建，还是 A17 构建也会卡动画？** 这个问题今天无人能答，而它决定矩阵走哪一半。

### 5.2 现场部分（30 秒，四类互斥）

判据（四条独立，不靠主观描述）：

1. **两次间隔 ≥5 s 的截图/录屏比对** —— 画面是否逐帧变化（判"动画在播"）。
2. **秒表计时** —— 到首次自重启的秒数（<30 s ⇒ B）。
3. **是否回落 fastboot** —— 屏幕出现 fastboot 字样 **且** `fastboot devices` 有输出（⇒ C）。
4. **`adb devices`** —— 非空且为 `device` ⇒ 已过 init，属 userspace 域。

| 类别 | 定义 | 故障域 | 矩阵走哪半 |
|---|---|---|---|
| **A 卡动画** | 画面逐帧变化，≥15 min 无回落 | userspace（init 之后） | userspace 臂全部有效 |
| **B 重启循环** | 有画面 → 数秒自重启 → 重复（≥3 次） | 内核 / 早期 userspace | 先取 pstore（§4），再定 |
| **C 卡第一屏** | logo 静止，~160 s 后回落 fastboot | bootloader / early kernel | **userspace 臂无效**，改走 boot/模块/slot |
| **D 无显示** | 全黑，无 logo | bootloader / 硬件 | 全部实验无效，先查 vbmeta/slot/供电 |

**纪律**：症状类别不同的两次复现之间，**禁止沿用任何"已排除"**（`§33` 的十条排除表正是在跨症状下继承的，已全部降级）。

---

## 6 v4 主表（编号连续 1–17；缺号说明见 §6.2）

| # | 目的 | 改动 / 命令 | 能排除什么 | 恢复 | 耗时 | 风险 | 前置 |
|---|---|---|---|---|---|---|---|
| **1** | **G0 症状归属确认**（门禁，非实验） | §5.1 离线台账 + §5.2 现场四类判定 | 决定后面 16 条哪一半有效 | 无 | 离线 30 min + 现场 30 s | 无 | — |
| 2 | O1 四次复现的指纹对账（离线） | §5.1 表逐行填 | 把"卡动画"钉到具体 blobs 世代 | 无 | 40 min | 无 | — |
| 3 | O2 两侧 `security_patch` 比对（离线） | LOS `system/build.prop` 的 `ro.build.version.security_patch` vs `getvar` 的 `security-patch-level:2026-02-01` | **若 LOS SPL ≥ 2026-02-01 ⇒ "降级触发 key blob version binding 失效"机制不成立，候选 B 当场死亡** | 无 | 20 min | 无 | — |
| 4 | O3 模块集合 / KMI 对账（离线） | 用 `_work/erofsmini.py` 解 `vendor_dlkm`/`system_dlkm`，核 `lib/modules/<ver>/` 目录名 == 内核 banner、`modules.dep` 完整、vermagic 一致 | 若不一致 ⇒ **直接解释"卡第一屏"**（报告已记该场景实证过一次：A17 内核 + A16 模块） | 无 | 60 min | 无 | #1 |
| 5 | O4 bootconfig / cmdline 比对（离线） | 两侧 `vendor_boot` bootconfig 逐项 diff（重点 `androidboot.serialconsole`、`log_level`） | 若 serialconsole 被删 ⇒ 串口通道存在性；决定"零日志"是否真是硬约束 | 无 | 30 min | 无 | — |
| 6 | D1 `adb devices` 复查（原 E-1） | `adb devices` / `fastboot devices` | 唯一能推翻"零日志"前提的观测 | 无 | 10 s | 无 | — |
| 7 | **D2 读数侧自检 + ramoops/pmsg 读取** | §4.2 第 0 步三条命令；有值则 `cat /sys/fs/pstore/console-ramoops-0` 落盘（环形缓冲，末几行即卡点） | 有值且见 panic/oops ⇒ 内核层定案，userspace 臂全排除；有值但日志戛然而止 ⇒ 直接给出卡点位置 | 无 | 5 min | 无 | #1 |
| 8 | D3 `/data` 当前状态只读四态判定 | TWRP 只读挂载 + `dmesg`；结论记四态之一（可解密 / 密文 / 空分区 / 无法判定） | 建立"孤儿密文 or 正常加密"这一事实，供 #17 判读 | 无 | 10 min | 低 | #7 |
| 9 | D4 `fastboot getvar all`（早于任何写） | `fastboot getvar all > logs/<UTC>-getvar.txt` | slot / 分区尺寸 / SPL 基线；**必须早于 #16（污染 slot）** | 无 | 1 min | 无 | — |
| 10 | D5 `fastboot oem` 日志通道枚举（原 X4） | `fastboot oem ?` 枚举 → 若存在日志/ramdump 命令则取 | 拿到内核日志即知 `mount_all` 返回码；**零改动、可能一步定案** | 无 | 15 min | 低 | — |
| 11 | F1 无 wipe 复现刷入（**只为取日志**） | 用**最新 A17 构建**（`pandora-dt` 那份从未刷过）刷入，**不 wipe**；复现后第一件事是回 TWRP 做 #7 | 提供一次"指纹已知 + 症状已知 + 有读数侧"的干净复现；是 #2/#3/#4 结论的验证场 | 重刷 stock（270 s） | 40 min | 中 | #1 判 A/B；#7 读数侧自检通过 |
| 12 | F2 E2 → E2b SELinux 两臂 | `permissive=1` → 仍卡则上 seccomp 放宽；校验镜像内策略哈希 | sepolicy 缺口 / seccomp 缺口 | 重刷 boot/vendor_boot | 2×20 min | 中 | **必须在任何 wipe 之前**；#1=A/B |
| 13 | F3 E7 / X5 关 bootanim 判前提 | 关 bootanim 后看屏幕（全黑 ⇒ 前提实证；仍播同一动画 ⇒ 前提崩） | 报告五章共享的"逐帧动画"前提 | 重刷 boot | 15 min | 中 | #1=A |
| 14 | **F4 A1 `atgc` 单 token 消融**（新） | 解包 LOS `vendor_boot` → `first_stage_ramdisk/fstab.qcom` 删掉 `/data` 行的 `,atgc` → 重打包 → **单刷 vendor_boot** | 唯一残留的 fstab 侧变量：能起 ⇒ `atgc` 运行时前置不满足（根因定案）；仍卡 ⇒ fstab 侧彻底清零 | 重刷原 vendor_boot（可复现） | 25 min | 低（单分区、完全可逆） | #1=A/B；#7 读数侧可用（否则失败也读不到原因） |
| 15 | F5 E3 / X1 vendor 对称臂（成对） | E3：LOS system + 原厂 vendor；X1：LOS 全部 + 只回刷原厂 vendor | 解耦 vendor blobs 与 framework；**成对做才有判别力**（单做只能得"该混合组合能起"） | 重刷对应分区 | 2×20 min | 中 | #1=A/B；#12 之后 |
| 16 | F6 E4 slot 切换 | 切槽后重刷复现 | 引导槽位/AVB 链 | 切回 | 20 min | 中（**污染 slot 证据**） | **必须晚于 #9** |
| 17 | **F7 E1c 真 format userdata**（唯一不可逆） | `fastboot erase metadata`（空操作）→ `fastboot erase userdata` → `fastboot reboot` | /data 侧假设的**第一次真正否证**（见 §3.3） | `restore_stock_full.sh`（须实测） | 40 min | **不可逆** | #1=A/B；#1–#16 全完成；书面签收 |

### 6.1 顺序纪律（不可让渡）

1. **不可逆排最后**：只有 #17。
2. **E2/E2b（#12）先于任何 wipe**：先 wipe 则"permissive 后能起"无法区分"sepolicy 缺口"与"wipe 本身就好了"，且该混淆事后不可剥离。
3. **`getvar all`（#9）早于会污染 slot 的实验（#16）**。
4. **读数侧自检（#7）早于任何"以 pstore 为空为判据"的结论**。
5. **先读后写**：一切只读（#2–#10）先于一切写入（#11–#17）。
6. **warm reset 收尾**：一律 `fastboot reboot`，禁止长按电源（`PSTORE_BLK` 未配置，掉电即失）。
7. **复现后第一动作是回 TWRP 读 pstore，不是恢复设备**——本次事故最痛的教训就是"先恢复、后取证"。

### 6.2 编号与缺号说明

- v4 编号 1–17 连续。`E0`（静态先验）已移出实验表——它是输入，不是实验。
- v2 的 `E5` / `E6` 属历史缺号，内容不可考，**不追溯补号**；v4 不复用这两个编号，以免审计链出现"同名不同义"。
- 新旧对照：`E-1→6`｜`X2→取消`｜`X4→10`｜`E2/E2b→12`｜`E7/X5→13`｜`E3/X1→15`｜`E4→16`｜`E1a→取消`｜`E1b→取消（由 17 取代）`｜`X3→并入 7/11`（`logd.logpersistd` 写 `/data` 在 /data 解不开时无解，故 X3 只保留 pmsg 路线）。

---

## 7 判定表：四态 + 观测窗口

**观测窗口（全表统一）**：`≥15 分钟`内 `sys.boot_completed` 无变化 ⇒ 判**卡**；同时记录**动画是否仍逐帧**（两次间隔 ≥5 s 截图比对）。重启循环以**≥3 次自重启**为判据。

| 实验 | 通过 | 失败 | **无效**（不得记为排除） | **S0**（已执行但不可采信） |
|---|---|---|---|---|
| 1 G0 | 四类判定唯一且与指纹同批记录 | 无法归入四类 | 未录屏/无计时；屏幕现象仅凭事后回忆 | 18:26 之后那次"未知症状"复现 |
| 2 O1 | 每行字段齐全且互不矛盾 | 出现两行同指纹不同症状 | 缺 `build.prop` 或无 zip | §27 那次（"清 data"未定义） |
| 3 O2 | 拿到两侧 SPL 并出结论 | LOS SPL < stock SPL（机制存活） | 取不到 LOS `build.prop` | — |
| 4 O3 | 目录名/vermagic/dep 三项全核 | 任一项不一致 | erofs 解析失败（工具问题，非阴性） | — |
| 5 O4 | 两侧 bootconfig 逐项 diff 完成 | serialconsole 被删且串口不可用 | 取不到 bootconfig | — |
| 6 D1 | `adb devices` 见 `device` | 空列表且两处均挂不上 | 主机 udev 未装致误报空 | — |
| 7 D2 | 读数侧注册 + 取到非空记录并完成内容判读 | 读数侧注册但记录为空（按 §4.2 表判读力，且优先怀疑内核未打印） | **读数侧未注册**（`/sys/fs/pstore` 天生空） | 本次事故 TWRP 的"pstore 为空"——读数侧从未验证，**降级为 S0** |
| 8 D3 | 四态之一明确 | — | TWRP 挂不上且 dmesg 无信息 | — |
| 9 D4 | `getvar all` 全量落盘、退出码 0 | — | 只抓到片段 | — |
| 10 D5 | 枚举到日志通道并取到内容 | 枚举到但无内容 | `oem ?` 全部 unsupported | — |
| 11 F1 | 症状可复现且四要素齐全 | 不复现（能起） | 复现了但读数侧不可用 ⇒ 白刷 | — |
| 12 F2 | `permissive=0→1` 且能进系统 | 转 1 但仍卡 | 仍为 0；或 `SELinux: Could not load policy` | — |
| 13 F3 | 屏幕无 bootanimation 输出 | 仍见逐帧动画 | 属性未被读到（须确认 `service.bootanim.exit` 实际值） | — |
| 14 F4 | 删 `atgc` 后能起 | 仍卡（fstab 侧清零） | 镜像未被真正刷入（须核 vendor_boot sha256） | — |
| 15 F5 | 混合配置能起 | 仍卡 | 原厂 boot 未起 fastbootd；装错槽 | — |
| 16 F6 | 切槽后行为可解释 | 仍卡且与切槽无关 | 槽位未真正切换 | — |
| 17 F7 | 擦除后由 LOS 自身重建 /data 并起 | 仍卡（/data 侧否证） | `erase userdata` 返回 FAILED；或擦完仍未到 userspace | — |

**无效态一律不得记为"排除"**——这是 v2 定的规矩，v4 继续执行，并且新增一条：**"观测通道未验证"本身就是无效态的充分条件**（第 7 行）。

---

## 8 回归验证清单（证明"修好了"而非"碰巧好了"）

1. **单变量修复**：只改一处（若是 E1c 结论，则只做 wipe，其余镜像一字节不改）。
2. **反向复现（最关键）**：刷回原厂 A17 → 由原厂重建 /data → 再刷 LOS **不 wipe** → **故障必须复现**。只做正向不做反向，等于没证明因果。
3. **循环 ≥2 次**：正向 2/2、反向 2/2；否则结论降级为"相关"。
4. **症状同类**：反向复现的症状类别必须与正向**同类**（§5.2）。跨症状（卡动画 vs 重启循环）不得记为"复现成功"。
5. **两臂对照**：分别验"只擦 userdata 保留 metadata"与"只擦 metadata 保留 userdata"，确认**只有前者修复**（后者正是 10-27 已发生的状态，预期无效）。
6. **时间窗口**：修复后 ≥3 次完整重启，含 ≥1 次冷启动（关机再开，而非 `fastboot reboot`）。
7. **判据锚点**：须同时满足 `sys.boot_completed=1`、vold 解密成功行、`nonencrypted` 触发记录；**不以"看到 launcher"为通过**。
8. **台账回填**：结论落盘时标注"新增 / 修正 §27 / 修正 §31 / 修正 §33"，防止下一轮再把已知阴性当未知。

**不可逆实验（#17）前落盘清单**：① G0 四类判定；② `getvar all` 全量；③ `#7` 读数侧自检结果 + pstore/pmsg 内容；④ `#8` /data 四态；⑤ 依赖"症状稳定"的全部判读；⑥ `restore_stock_full.sh` **实测**可用（不能只在纸面假设 270 秒可回滚）。

---

## 9 结论：v4 是否已收敛？

**两条都说：离线已榨干，定案必须刷机——但刷机的目的已经不是原来那个。**

**离线侧（#2–#5）已到边际**。A 证明配置侧（fstab）逐行等价；B 证明取证通道配置层存在；C 证明过去三次"清 data"没碰过 userdata。这三条合起来意味着：**继续在镜像里找差异，能找到的只有 #3（SPL）与 #4（KMI）两个点**，而这两个点即使全部核清，也只能把候选从 5 条压到 3 条左右——因为剩下的候选（HAL 域缺失 / VINTF 不匹配 / VNDK 废弃）**在镜像里不可判定**，它们只在运行时以 avc / vintf 报错的形式出现。

**所以必须刷机，但唯一正当的目的是"取回日志"，不是"验证 /data"**：

- 今天唯一的结构性障碍是**零日志**（报告自述"继续盲试的收益已经为零"）。结论 B 给了新信息：LOS 内核里 pstore 通道是开的，`PSTORE_CONSOLE=y` + `PSTORE_PMSG=y`。
- 因此最高性价比的动作是 **#7（读数侧自检）+ #11（无 wipe 复现，只为取日志）**，而不是任何 wipe。
- 若 #7 自检发现 TWRP 侧不注册 ramoops，那么"pstore 为空"这条历史观测**当场作废**，须改走 #10（oem 日志）或 #5（serialconsole）；此时**不得**再引用"pstore 为空"作为任何结论的依据。

**风险提示（v4 最想让人记住的一句）**：在当前证据状态下，做 wipe 是**在没有任何一条日志的情况下，用不可逆操作去猜一个已被 A 否证了一半的假设**。E1c 是必要的，但它是第 17 条，不是第 1 条。

---

> 本矩阵为只读分析产物，未执行任何设备操作；结论 A 的复核脚本与产物见 `deliverables/gstack/_work/extract_fstab.py`、`fstab-qcom-los.txt`、`fstab-qcom-stock.txt`。
