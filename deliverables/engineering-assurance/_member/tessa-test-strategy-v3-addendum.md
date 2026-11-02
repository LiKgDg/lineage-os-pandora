# 验证策略评估 v3 补遗：三条推翻 v2 判读的实证更正

**评估人**：泰莎（Tessa）· 测试专家
**性质**：定稿前的更正备忘。v2 主体仍有效，但下列三条**推翻 v2 的判读**，其中 D1 会改变结论方向。
**来源**：`docs/flash-log-1458.txt`（已核原文）、`flash-log-1609` / `v32-1809`（同形态）、cody 与 rex 的独立核对。

---

## D1　`fastboot -w` 从未擦过 userdata（已核原始日志）

`flash-log-1458.txt` 第 42–47 行原文：

```
== 清空 userdata（fastboot -w）==
  Erasing 'metadata'      OKAY [ 4.020s]
  Erase successful, but not automatically formatting.
  File system type raw not supported.
✓ userdata 已清空          ← 脚本自报，工具没做
```

**没有任何一行涉及 userdata。** 脚本第 47 行打印的「✓ userdata 已清空」是假成功。

三个连带更正：

1. **E1b 的两个成分都已被执行过**。`fastboot -w` 在此环境下只做 `erase metadata`，而 E1b 定义为「`erase metadata` + `-w`」——两者已被同一次操作覆盖。E1b 不是待做实验，是**已执行且已造成不可逆后果**。
2. **§27「清 data 后仍卡住」不是阴性结果，是 S0（实验从未执行）**。v2 中我把 H1 标为 ⊘（伪覆盖）的裁定**作废**，应改标 **S0 / 历史失效实例**。它的价值是证明「这个坑真实发生过」，不是提供先验概率。
3. **v2 中「H2 是异症状阴性」同样不成立**。H2 的 `-w` 也只抹了 metadata。

---

## D2　当前 /data 是「密钥已毁、密文尚存」的孤儿密文

这是本项目从未命名过的状态，且它带来一个 v2 完全没有的机制候选。

`-w` 抹掉 `/metadata`（metadata 加密密钥容器）而 userdata 密文仍在 → `/data` 在任何系统上都不可解密，直到被 format。

**关键不对称**：同一处理下，**原厂 A17 能正常启动**（build-notes §31：首次启动 3 分 20 秒、「需重新初始化」），**LOS 不能**。

若原厂是在「解不开」的情况下把 /data 重建了起来，那么两边差别只可能在**解不开时的处置**：

- stock 的 `fstab.qcom` userdata 行含 `formattable` → 解不开就重建；
- LOS 若无 `formattable`，或 vold 在 metadata 解密失败分支选择放弃而非重建 → `mount_all` FAIL → `nonencrypted` 永不触发 → 卡动画。

**这个假设比「key blob version binding 失效」解释力更强**：它与三次观测（H1 卡动画、H2 重启循环、stock 正常）全部相容，而 version binding 无法解释 stock 为何正常。

---

## D3　最有价值的实验不是 E1a/E1b，是一个零成本离线比对

| 项 | 内容 |
|---|---|
| 做什么 | 比对 stock 与 LOS 两侧 `fstab.qcom` 的 **userdata 行 flags 集合**（`check` / `formattable` / `latemount` / `wait` / `forceencrypt` / `encryption=` 的有无与组合）；再核 vold 在 metadata 解密失败分支的处置（重试 / 放弃 / 触发 format） |
| 成本 | 零。不需设备、不需复现、不消耗任何不可逆额度 |
| 能定案什么 | 若 `formattable` 或失败分支存在差异 → **根因当场成立**，且不需要任何 E1a/E1b |
| 注意 | 报告已比对过加密参数且一致——**本项比对的是 flags 集合与失败分支，不是加密参数**，不重复 |

**地位调整**：v2 中 X2（TWRP 只读 key blob mtime）原本是「判定假设生死」的门禁。现在降级为「确认孤儿密文状态」的辅助读数；真正的门禁应让位给本项离线比对。

---

## D4　现场已灭失，矩阵性质必须改写

build-notes §31–§34 记：设备已恢复原厂 A17、super 整体重写、`/data` 与 `/metadata` 已被覆盖。

因此 v2 中所有依赖 mtime / dropbox 时间戳 / tombstone 的取证路径，**对现有现场全部失效**。矩阵性质从「对现有现场取证」变为「**再现场景下的对照实验**」，快照纪律与恢复路径须按后者重写。

连带失效项：v2 §8「不可逆实验前落盘清单」第 ③ 项（五处快照）、第 ⑤ 项（X2 的 mtime 读数）在当前现场已不可执行。

---

## D5　ramoops 两说冲突未决（定稿前必须二选一）

- build-notes §33：pstore 为空因「**内核未配置 ramoops**」。
- 报告 1.8.3 / 5.2：「ramoops 链路完整，只是无 ECC，用户态 hang 不触发 kmsg_dump」。

两说互斥。若笔记为准，v2 §7 中 P0 的「TWRP 只读取证链（pstore → pmsg → tombstones → dropbox）」**整条不存在**——行动清单第一条会指向一个不存在的证据源。

核对方法（产物侧，无需设备）：`zcat /proc/config.gz | grep -i ramoops`，或解包内核 `.config` 查 `CONFIG_PSTORE_RAM`。

---

## D6　症状不唯一，基线本身待确认

rex 核出四次复现是**四种症状**：卡动画 / 重启循环 / 卡第一屏 160 s 回落 fastboot / 未知；且 11-01 18:26 之后**完全没有刷机日志**。

故「当前卡动画」这一基线未经确认。若实际症状是「卡第一屏回落 fastboot」，故障域在 bootloader / kernel 层，**矩阵里全部 userspace 臂被绕过**。矩阵第一行应改为「症状归属确认」。

---

## D7　样本量修正

`flash-log-1608.txt` 是被取消的（`✗ 已取消`），不计入复现次数。任何按「已复现 N 次」设样本量的判读，N 须减一。

---

## 对已定稿报告的最小修改建议（按性价比排序）

| 序 | 位置 | 问题 | 性质 |
|---|---|---|---|
| 1 | 报告 4.3 / 结论 | 「最后刷 LOS 未 wipe，原厂加密的 /data 被直接接管」——**被日志否证**：`-w` 只抹 metadata，且 userdata 从未被擦 | **会导致结论方向错误，必须改** |
| 2 | 报告 5.2 | pstore 为空的机制解释需按 D5 二选一 | 证据源存在性，必须改 |
| 3 | 报告 5.7 | E1a/E1b 需按 D1 降级为「已执行 / 已造成不可逆后果」，并补 D3 的离线比对 | 实验设计，强烈建议 |

---

## 与 cody / rex 的口径统一

- 四态拆分（S0 / S1 / S2 / S3 / 无法判定）成立；cody 增加的一维（系统侧可观测量，把「卡动画」与「重启循环」分开）成立，**采纳**。
- 唯一改动：**S0 从「可能的边界情况」升级为「已确认发生过的实例」**（§27 即 S0）。
- rex 的「E1b 假阳性定案风险」与我 v2 的 S1-2 同向，合并为一条：**E1b 必然"成功"，但成功只证明 format 有效，不证明原故障是 /data**。
