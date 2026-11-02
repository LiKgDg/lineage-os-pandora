# D4 启动验证预案（pandora / LineageOS 24.0）

> **这是一份预案，不是结论。** 截至 2026-11-02，D4（刷入并启动）从未通过，历史上刷入后停在开机动画。
> 本文的目标只有一个：下次有人拿着这台设备、照着做就能跑，并且**失败时能立刻判断失败在哪一层、怎么回滚**。
>
> 关联文档：`README.md` §7.1（整包路径）、`docs/los24-build-notes.md` §29–§31（逻辑分区与恢复实测）、
> §35（vendor 树 `Android.bp` 是陈旧产物）、`deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md`（根因定案）。
> 本文不引入任何新脚本：刷用 `scripts/flash/flash_fastboot_package.sh`，回滚用 `scripts/flash/restore_stock_full.sh`。

---

## 一、前置条件

### 1.1 设备状态

| 项 | 要求 | 现状 | 依据 |
|---|---|---|---|
| 系统 | 能正常进原厂 A17（OS4.0.5.0.XBLCNXM） | 可用（团队核实，未在本预案中复查） | 任务背景；恢复指纹见 §4.3 |
| bootloader | 已解锁（`ro.boot.verifiedbootstate=orange`） | 已解锁 | `docs/los24-build-notes.md` §30/§31 恢复记录 |
| recovery | 可能是原厂，也可能是 TWRP 3.7.1 | **未核实**：§30 遗留记录为 TWRP，但 §31 的恢复流程刷过原厂 `recovery.img`（`stock-a17/recovery.img` 时间戳 11-01 17:17） | 无论当前是哪一个，回滚脚本都会写回原厂 |
| 电量 | ≥ 4200 mV（`fastboot getvar battery-voltage`） | **未核实**（G4 会硬性拦） | `scripts/flash/flash_fastboot_package.sh` G4 |
| 连接 | 数据线直连主板 USB 口；刷机全程 10–20 分钟不断线 | 未核实 | 同上，掉电/断线是变砖风险 |

> 这台设备是**唯一的验证设备**。刷坏之后没有第二台可以对拍，所以第 4 节的回滚不是备选方案，是前置条件的一部分。

### 1.2 权限与工具

| 项 | 要求 | 实测值 | 备注 |
|---|---|---|---|
| fastboot | 主版本 ≥ 34（否则静默忽略 `fastboot-info.txt`） | `fastboot version 37.0.1-15733141` | 本机 `platform-tools/`，实测命令输出 |
| adb | 能用（判据与取证依赖它） | `1.0.41 / 37.0.1`，设备序列号 `fd3af370` | 任务背景 |
| adb 授权 | 设备侧已允许调试 | 未核实 | 许可失效时 `adb devices` 显示 `unauthorized` |
| KernelSU `su` | **可不用**。仅在需要读 `persist`/`devinfo` 这类分区时用 | 可用（`context=u:r:ksu:s0`） | 本预案的刷机与判据都不依赖 root |
| 小米账号 / EDL 授权 | 不需要（本预案不写固件分区） | — | 见 §5「只能靠 stock 包恢复」 |

### 1.3 产物（刷机前必须逐条 `ls` 确认）

| 用途 | 路径 | 校验值 |
|---|---|---|
| 待刷整包 | `releases/Fastboot_lineage_pandora-20261102-1426.zip` | 1,461,896,165 B；`sha256 60edf82a9f1b48cb41e5d46cd0d5f6cba60499e0ea0dd244a5824bf9a76b7835` |
| 包内结构 | 同上 | 18 个成员，解压合计 3,204,475,427 B；`fastboot-info.txt` 含 `update-super` + `if-wipe erase userdata` + `if-wipe erase metadata`（`unzip -p` 实测）；**包内没有 `mi_ext.img`**（刷写清单里也没有 `mi_ext`），它是原厂专有分区，内容能不能在 `update-super` 后存活**未核实**——见 §2.4 的 `mi_ext` 判据 |
| 回滚 · 物理分区 | `D:/WSL/out/pandora/stock-a17/` 的 7 个 `.img` | 实测存在：`boot` 100,663,296 / `init_boot` 8,388,608 / `dtbo` 23,068,672 / `vendor_boot` 100,663,296 / `recovery` 104,857,600 / `vbmeta` 12,288 / `vbmeta_system` 4,096 B |
| 回滚 · super | `D:/WSL/out/pandora/stock-super/super.img` | 实测存在：11,033,512,324 B 稀疏镜像（展开 13,421,772,800 B，与 §31 记录一致） |
| 回滚材料重建源 | 仓库根 `pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip` | `.gitignore` 排除（`*.zip`），不入库 |

**回滚材料不齐就不开刷。** 缺任一项，先用 `tools/payload_dump.py` 从上面那份原厂 OTA 重新解出
（`boot init_boot dtbo vendor_boot recovery vbmeta vbmeta_system` 七个物理分区 + 七个逻辑分区再 `lpmake` 成 super，
做法见 `docs/los24-build-notes.md` §31），补齐后再回到本预案第 0 步。

### 1.4 这一步会丢掉什么（先讲清再动手）

包内 `fastboot-info.txt` 里有 `if-wipe erase userdata` 与 `if-wipe erase metadata`，
`fastboot -w update` 会真的执行它——**设备上所有用户数据、已装应用、照片、聊天记录全部不可恢复**。
`/data` 的第三方应用私有数据没有通用备份手段，只能靠应用自带云同步或导出，
必须在刷前由使用者自己完成；这一步本预案无法代劳，也无法事后补救。

---

## 二、验证目标与判据

目标不是「能开机」，而是「**在时间窗内进到可用系统，并且内核/AVB/分区/模块四层都对得上**」。
判据分四层，前一层不过就不必看下一层——这样失败时能直接定位是哪一环，而不是笼统地说"起不来"。

### 2.1 L0 刷入层（脚本自动判）

| 判据 | 观测 | 通过阈值 |
|---|---|---|
| fastboot 退出码 | 脚本 `tee` 的日志 `docs/logs/<UTC>-flash-package.log` | 0 |
| wipe 真发生 | 日志里 `Erasing 'userdata'` **和** `Erasing 'metadata'` | 两条都在 |
| super 被重写 | 日志里有 `Sending sparse 'super'` / `update-super` / `Resizing 'super'` 之一 | 至少一条 |
| 没写固件分区 | 日志里 `Sending '<分区>'` 的集合 | 不含 `abl` `xbl` `tz` `uefi` 等 `FW_BLACK` 名单 |
| 无失败行 | 日志 | 无 `FAILED` |

### 2.2 L1 设备回到系统侧

| 判据 | 命令 | 通过阈值 |
|---|---|---|
| adb 出现 | `./platform-tools/adb.exe devices` | 出现 `fd3af370`（或新序列号）且状态为 `device` |
| 时限 | 从刷入结束起算 | **≤ 20 分钟**（脚本末尾提示：首次启动含 dexopt，3–20 分钟；历史上原厂 super 整体重写后首次启动约 3 分 20 秒，§31） |

### 2.3 L2 系统起来

| 判据 | 命令 | 通过阈值 |
|---|---|---|
| `boot_completed` | `adb shell getprop sys.boot_completed` | 输出 `1`；60 秒后复采仍是 `1` |
| 不做无限等待 | `adb wait-for-device` 必须套 `timeout` | 超时即按 §4.1 判失败，不要挂着等 |

### 2.4 L3 关键状态（逐项对拍，任一项不符即记录为哪一环出问题）

| 检查 | 命令 | 期望值 / 判据 |
|---|---|---|
| 内核世代 | `adb shell uname -r` | `6.12.69-android16-6-*`（与 `verify_kernel_modules.sh` 的 `EXPECT_KMI` 同源；出现 `6.12.23-android16-5` = 模块/内核又错配） |
| AVB 状态 | `adb shell getprop ro.boot.verifiedbootstate` | `orange`（已解锁）。出现 `green` 说明 vbmeta 没被换成 LOS 的，刷入链路可疑 |
| 机型 | `adb shell getprop ro.product.device` | `pandora` |
| wipe 确证 | `adb shell ls /data/local/tmp/WIPE_CANARY-* /sdcard/WIPE_CANARY-*` | 两个都不存在 = wipe 真发生。⚠ 刷前 adb 不通时 G5 不会投放金丝雀，此项只能靠 L0 日志 |
| 8 个逻辑分区挂载 | `adb shell cat /proc/mounts`（过滤 `/system /system_ext /product /vendor /odm /vendor_dlkm /system_dlkm /mi_ext`） | 全部存在且以 `erofs`（或 `ext4`）挂载。**`mi_ext` 要单独看**：包内没有 `mi_ext.img`，`update-super` 之后它是否还完整**未核实**。若 `mi_ext` 缺失或挂不上，先查刷机日志里的 `Resizing 'super'` / `update-super` 行，再看 super metadata（`adb shell lpdump`，该命令是否在设备 PATH 上未核实），不要直接归因到 ROM |
| 模块真加载 | `adb shell lsmod`（存全文）与 `adb shell lsmod \| wc -l` | 条目数与包内 `modules.load` 同量级（参考量级：`vendor_boot` 461 条 / `vendor_dlkm` 402 条，见 README 未完成表）。个位数或 0 条 = KMI 仍不通，此时即使 `boot_completed=1` 也判"半启动"，不能算 D4 通过 |
| 无致命循环 | `adb logcat -d -b all \| grep -cE "FATAL EXCEPTION\|init: Service .* exited\|Rebooting"` | 间隔 120 秒采两次，计数**不增长** |
| 稳定性 | `adb shell cat /proc/uptime` | 刷入后 10 分钟仍在单调增长，没有重启归零 |
| 动画是否推进（旁证） | 间隔 10 秒 `adb exec-out screencap -p` 三张比 hash | 三张不全相同 = 逐帧推进；全相同 = 冻帧（脚本末尾同款判法） |

### 2.5 判「D4 通过」的完整条件

L0 全过 → L1 在 20 分钟内 adb 可见 → L2 `boot_completed=1` 且复采稳定 → L3 九项全部符合。
**只满足「能进桌面」不算通过**——历史上失败点就在模块世代，`lsmod` 为空同样能骗过肉眼看动画。

---

## 三、执行步骤

### Step 0 只读确认（不碰设备状态）

```bash
cd "C:/Users/MSI/Desktop/HB/1/2/2/lineage os"

./platform-tools/adb.exe devices                       # 期望 fd3af370  device
bash scripts/maintain/selfcheck.sh                     # 仓库自检，期望 exit 0
ls -l releases/Fastboot_lineage_pandora-20261102-1426.zip
sha256sum releases/Fastboot_lineage_pandora-20261102-1426.zip   # 对照 §1.3
unzip -p releases/Fastboot_lineage_pandora-20261102-1426.zip fastboot-info.txt
ls -l "D:/WSL/out/pandora/stock-a17" "D:/WSL/out/pandora/stock-super/super.img"   # 回滚材料
```

### Step 1 备份（唯一一次机会）

按 §1.4 完成应用层备份。确认后再继续。

### Step 2 进 bootloader

```bash
./platform-tools/adb.exe reboot bootloader        # 或关机后长按 电源 + 音量下
./platform-tools/fastboot.exe devices             # 必须恰好 1 台
./platform-tools/fastboot.exe getvar is-userspace # 必须是 no（bootloader）
```

整包**必须在 bootloader 下发起**：包内 `fastboot-info.txt` 的 `reboot fastboot` 会自己切到 fastbootd，
在 fastbootd 下发起会被 G4 拒（脚本退出码 2）。实测这台机器从 bootloader 手工
`fastboot reboot fastboot` 进不去 fastbootd（§30），所以别手工切。

### Step 3 过闸不刷（必做，约 1 分钟）

```bash
bash scripts/flash/flash_fastboot_package.sh --preflight
```

五道闸：G1 包结构（`fastboot-info.txt` / `update-super` / `if-wipe erase userdata`）、
G2 fastboot 主版本 ≥ 34、G3 镜像内无 `6.12.23-android16-5` 世代模块、
G4 设备状态（`is-userspace=no`、`product` 是 `pandora|canoe`、电量 ≥ 4200 mV）、
G5 证据基线（拉 `/sys/fs/pstore` 到 `docs/logs/<TS>-pstore-pre/`、投放 wipe 金丝雀）。

**G3 不过就不要往下走。** 那意味着结果不是"可能起不来"，而是"必然卡第一屏"（README §7.1）。

### Step 4 真刷

```bash
bash scripts/flash/flash_fastboot_package.sh        # 提示时输入 YES
echo $?                                             # 0 = 事后校验通过；1 = 日志审计没过；2 = 闸没过
```

### Step 5 等启动 + 按第二节采样

```bash
# 20 分钟上限，不要无限阻塞
timeout 1200 ./platform-tools/adb.exe wait-for-device

ADB=./platform-tools/adb.exe
$ADB shell getprop sys.boot_completed
$ADB shell 'getprop ro.build.fingerprint; getprop ro.boot.verifiedbootstate; getprop ro.product.device; uname -r'
$ADB shell 'ls /data/local/tmp/WIPE_CANARY-* /sdcard/WIPE_CANARY-* 2>&1'
$ADB shell 'cat /proc/mounts' > docs/logs/<UTC>-d4-mounts.txt
$ADB shell 'lsmod'            > docs/logs/<UTC>-d4-lsmod.txt
$ADB shell 'lsmod | wc -l'
$ADB logcat -d -b all         > docs/logs/<UTC>-d4-logcat.txt
$ADB shell 'cat /proc/uptime'
$ADB pull /sys/fs/pstore "docs/logs/<UTC>-pstore-post"
```

### Step 6 落结论

把 §2 每一格的实测值填进一张结论表（放 `docs/logs/`），并与刷前 `docs/logs/<TS>-pstore-pre/` 对比：
pstore 里出现**新**文件 = 本次启动产生了 panic/exception，那份栈就是最贵的证据（`panic_on_oops=1`、ramoops 跨重启保留，见 README 关键结论 12）。
纯 userspace 挂死留不下栈（`hung_task_panic=0`），这种情况只能靠 `logcat -b crash` 与 `init` 的 `Service ... exited` 计数。

---

## 四、失败判定与回滚

### 4.1 判失败的现象（任一命中即判失败，**不要叠加刷机**）

| 现象 | 出现时间点 | 说明 |
|---|---|---|
| 刷入过程有 `FAILED`，或脚本退出码 1/2 | 刷入中/刷完 | 先读日志第一条 `FAILED`；退出码 2 是闸没过（多数是电量、fastbootd、包结构） |
| 事后校验报「没有 `Erasing 'userdata'`」 | 刷完立即 | wipe 没发生 → 本次实验**无效**，后续任何现象都不能当 ROM 缺陷（老 fastboot 静默降级的典型） |
| 20 分钟仍无 adb | T+20 min | 判失败，进 §4.2 |
| 动画反复从头开始（重启循环） | 全程 | §31 的历史形态：内核起来了，几秒后 panic/reset |
| 卡第一屏冻帧（三张截图 hash 全同、无 adb） | T+10 min | §29 的典型形态：KMI 不通，first-stage 拿不到存储/显示驱动 |
| adb 有了但 `boot_completed` 恒空/0，`system_server` 反复崩 | T+20 min | 记 `logcat -b crash`，判"半启动" |
| `lsmod` 空/个位数但界面能进 | 通过后复查 | 判**不通过**：模块世代问题被掩盖，后续功能会零散失效 |

### 4.2 回滚到原厂

前提：还能进 bootloader（`fastboot devices` 恰好 1 台、`getvar is-userspace` = `no`）。

```bash
bash scripts/flash/restore_stock_full.sh
```

它一次做 8 步：7 个物理分区（`boot init_boot dtbo vendor_boot recovery vbmeta_system vbmeta`，vbmeta 放最后）
+ `super`（`D:/WSL/out/pandora/stock-super/super.img`）。退出码即成败，全程 bootloader 模式，
**不需要 fastbootd**——这正是它能救回"fastbootd 进不去"现场的原因（§31）。

> **不要用 `scripts/flash/restore_stock_a17.sh` 收尾。** 它只刷 6 个物理分区，既没有 `recovery`，
> 也没有 `super`。本次整包刷入执行过 `update-super`，逻辑分区已经是 LOS 的；只用它恢复会得到
> 「LOS 的 super + 原厂 boot/vbmeta」，AVB 链与 ramdisk 都对不上——§30 踩的就是这个坑。
> 它只在"只刷过物理分区、super 从未被动"的场景下够用。

`fastboot devices` 为空时按顺序试：

1. 长按电源 10 秒断电，再长按 电源 + 音量下 10 秒重进 bootloader；重试 `fastboot devices`；
2. 换 USB 口（优先主板直连口）、换一根确认能传数据的线；重试；
3. 仍不可见 → 只能 EDL / 售后。**EDL 需要授权账号，本项目不具备**。这是唯一不可自救的分支（§5）。

### 4.3 回滚后如何确认真的恢复了

```bash
ADB=./platform-tools/adb.exe
timeout 600 $ADB wait-for-device
$ADB shell getprop ro.build.fingerprint      # Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM:user/release-keys
$ADB shell uname -r                          # 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
$ADB shell getprop ro.boot.verifiedbootstate # orange
$ADB shell getprop sys.boot_completed        # 1
```

这四项正是 §30/§31 记录的成功恢复指纹（fingerprint / uname / verifiedbootstate / boot_completed），逐字对照，不要凭"看起来正常"。
首次启动约 3 分 20 秒（super 整体重写后要重新初始化），超过 10 分钟没起来按 §4.1 重新判。

另外确认 recovery 也回原厂：`$ADB reboot recovery` 后不应出现 TWRP 界面
（回滚脚本会把 `recovery` 一起写回原厂；如果设备当前还是 TWRP 3.7.1，这一步是关键变化）。

---

## 五、风险清单

| 风险 | 触发条件 | 后果 | 缓解措施 |
|---|---|---|---|
| **丢用户数据** | 包内 `if-wipe erase userdata` + `erase metadata`（实测） | 不可恢复 | 刷前完成 §1.4 备份；明确告知这是"清机"操作；G5 金丝雀 + L0 日志双重确证 wipe 真的发生了 |
| **进不了 fastboot** | bootloader 被写坏 / 反复复位 / USB 不稳 | 只能 EDL 或售后 | 不写固件分区（脚本 `FW_BLACK` 硬闸 + 事后日志审计）；电量 ≥ 4200 mV（G4）；线材与 USB 口固定；绝不刷带 `abl`/`xbl`/`tz`/`uefi` 的第三方包 |
| **AVB 红字 / 校验失败** | vbmeta 与 system/vendor/odm 不同源 | 红字提示；连续失败启动会触发回退 | 整包一起刷（`flash --apply-vbmeta vbmeta` + `vbmeta_system` 都在包内），绝不"只刷一半"（§30）；不手工加 `--disable-verification` 掩盖问题 |
| **刷坏后只能靠 stock 包恢复** | 上述任一恶化 | 设备不可用，直到刷回 | 开刷前确认 §1.3 回滚材料在位；缺了先用 `payload_dump.py` 从原厂 OTA 重建；**材料不齐不开刷** |
| **wipe 假成功** | fastboot < v34 静默忽略 `fastboot-info.txt` | 屏幕与退出码都显示成功，实际 super 未更新、data 未擦 | G2 硬闸；本机 37.0.1 已过，但**换机器必须重查** |
| **在 fastbootd 发起整包** | 手工 `reboot fastboot` 后直接刷 | 包内 `reboot fastboot` 逻辑走不通 | G4 拦（要求 `is-userspace=no`） |
| **包与构建不一致** | 包是 20261102-1426 出的，之后又改过 `out/` | 结论对不上实际构建 | 刷前记下 §1.3 的 sha256；换包必须换一份记录并同步本文 |
| **单次结论被过度外推** | 一次成功或一次失败 | 误判设备树质量 | 见第六节的结论边界 |

---

## 六、已知阻塞项与结论边界

1. **机型 blobs 从未生成。** `vendor/xiaomi/pandora` 在整个项目里不存在（`README.md` 进度表标 ❌）；
   `vendor/xiaomi/sm8850-common` 的清单 1758 条里有 211 条在磁盘上没有实体（§35）。
   本整包的 `vendor.img`（672,915,456 B）与 `odm.img`（31,248,384 B）是从
   `out/target/product/pandora` 打进包的（`scripts/build/make_fastboot_package.sh`），
   而本机不存在 pandora 专属 blob 包，所以这两个镜像的内容只能来自 `sm8850-common` 的共用 blob。

   **结论边界：即使 D4 启动成功，也不能归因于「pandora 机型树配置正确」。**
   成功最多证明「`sm8850-common` 这套共用 blob + 本机型树 + A17 内核/模块」能起到可用系统，
   证明不了机型专属 blob 已齐、也证明不了每个配置项都对。
   反方向同样成立：**启动失败也不能直接判机型树配错**，要先按 §2 的四层判据定位失败落在 L1/L2/L3 哪一层。

2. **「补上那 206 条 blob 再来验 D4」这条路已实测不通。** 从 stock 镜像补 206 条会让构建挂在 soong，
   四层递进：`undefined module` → 依赖级联 → 删错模块 → `missing variant`（§35）。
   所以 D4 只能在当前这套 blob 上做，结论也只在当前这套 blob 上有效。

3. **`vendor/xiaomi/sm8850-common/Android.bp` 是陈旧产物**（747,836 B，由 211 个文件还在时的清单生成）。
   任何"顺手重生成一下"都会把树写坏（实测 747,836 → 23,316，且可能无可回滚备份）。
   要动这个目录先跑 `bash scripts/maintain/regen_makefiles.sh --check`，不要直接 `./setup-makefiles.py`。

4. **本次通过 = 什么，不通过 = 什么。**

   | | 能证明 | 不能证明 |
   |---|---|---|
   | D4 通过 | 当前这套产物能启动到可用系统；模块世代与内核真正对齐；整包刷入链路（`update-super` + wipe + vbmeta）在这台机器上生效 | 机型专属 blobs 齐全（没有）；设备树每一项都正确（只到"能起来"）；二次构建可复现（`out/` 与包的对应靠人工核对）；长期稳定性（判据只覆盖首启 10 分钟） |
   | D4 不通过 | 当前产物在这台设备上起不来，且失败点可分层定位 | 不能证明「LOS 24 在这台机器上不可行」。历史失败原因（模块世代）已定位并已修，这一次失败会是**新信息**，应按 §2 分层定位，而不是回到"再刷一遍试试" |

---

## 附：本文引用到的既有脚本与文档

| 用途 | 路径 |
|---|---|
| 刷整包（唯一刷机入口） | `scripts/flash/flash_fastboot_package.sh` |
| 完整回滚（物理 + super） | `scripts/flash/restore_stock_full.sh` |
| 仅物理分区恢复（不足以从整包回滚，见 §4.2） | `scripts/flash/restore_stock_a17.sh` |
| 模块世代门禁 | `scripts/maintain/verify_kernel_modules.sh`、`verify_index_ref.sh`、`kmi-gate.sh` |
| 仓库自检 | `scripts/maintain/selfcheck.sh` |
| 逻辑分区与恢复实测 | `docs/los24-build-notes.md` §29–§31 |
| 陈旧 `Android.bp` 与补 blob 的死路 | `docs/los24-build-notes.md` §35 |
| 根因定案（模块 KMI 错配） | `deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md` |
| 设备分区实测尺寸 | `docs/device-partitions.csv` |
| 脚本总索引 | `docs/scripts-index.md` |
