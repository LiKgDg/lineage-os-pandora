# LineageOS 24（Android 17）在小米 17 Pro 上卡开机动画的静态分析与根因定位

**日期**：2026-11-01
**执行模式**：完整（含审稿修订）
**研究对象**：小米 17 Pro（pandora / canoe / Qualcomm SM8850）

---

## ⚠️ 结论勘误（2026-11-02）

**本报告的最终结论已被后续离线取证推翻，阅读时请以本节为准。**

| 本报告原结论 | 2026-11-02 实测结论 | 依据 |
|---|---|---|
| 候选收敛为「`/data` 解密/挂载失败」与「`on boot` 之后的 userspace」 | **实际根因是内核模块 KMI 世代错配**：873 个 `.ko` 按 6.12.23 编译却装入 6.12.69 内核，`module_layout` CRC `0xe976b219` ≠ `0x797f2b3e`，`vendor_boot` 的 `modules.load` 150 条**可加载 0 条** | `deliverables/gstack/offline-evidence-closure-los24-kmi-2026-11-01.md` §2 |
| 第 2 章「模块层可排除」（清单一致 ⇒ 排除） | **该排除不成立**：清单一致 ≠ 内容一致，实测 411/461 内容不同 | 同上 §4 第 3 条 |
| 「原厂加密 `/data` 被 LOS 未 wipe 接管」 | **前提不成立**：`-w` 从未擦 userdata（日志中无 `Erasing 'userdata'`），只擦了 metadata | 同上 §3.3 |

**本报告仍然成立的部分**：第 1 章的 bootanim 机制与闸门链条、第 2 章关于 `same_magic`/CRC 判定顺序的源码分析（它恰好是本次根因的判据基础）、第 5 章的取证纪律与四类水位线失效。

**方法论教训**：第 2 章把「文件清单一致」当成了排除依据。清单是**摘要级证据**，只有哈希与 CRC 才是**排除级证据**。这条已写入 `deliverables/gstack/` 的流程建议。

---

## 目录

- [引言](#引言)
- [1. 故障域界定：从 bootanim 启动机制反推启动闸门](#1-故障域界定从-bootanim-启动机制反推启动闸门)
- [2. 镜像与模块层静态复核：boot/vendor_boot 结构与 GKI module_layout CRC](#2-镜像与模块层静态复核bootvendor_boot-结构与-gki-module_layout-crc)
- [3. 构建期契约缺口：A16 设备树与 A17 framework/blobs 的 VINTF、sepolicy、VNDK 比对](#3-构建期契约缺口a16-设备树与-a17-frameworkblobs-的-vintfsepolicvndk-比对)
- [4. 运行期数据状态：/data 与 /metadata 的跨大版本残留判定](#4-运行期数据状态data-与-metadata-的跨大版本残留判定)
- [5. 取证与实验设计：无 adb 条件下的证据提取与最小化验证](#5-取证与实验设计无-adb-条件下的证据提取与最小化验证)
- [结论](#结论)
- [参考文献](#参考文献)
- [待完善事项](#待完善事项)

---

## 引言

LineageOS 24 基于 Android 17（SDK 37），而小米 17 Pro（pandora / canoe / SM8850）当前可用的设备树仍派生自社区 TWRP 的 Android 16 时代配置。把 A17 的 system 与 vendor blobs 嫁接到 A16 设备树上，设备能正常显示开机动画，却永远停在动画上：adb 起不来，无串口，也不拆机取 UART——整个故障现场对研究者是"零日志"的。

本报告要回答的不是"ROM 为什么编译失败"，而是一个方法论问题：**在既无运行期日志、也无动态调试通道的条件下，静态分析能把一个 userspace 启动故障收敛到多细？**

约束本身决定了研究路径。既然无法观测，就只能从"哪些环节一旦失败，开机动画根本不可能出现"反向推理。而动画能显示本身就是一条强证据：它证明内核、first-stage init、SELinux 策略加载、apexd 与 SurfaceFlinger + display HAL 均已通过（[init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md)）；动画的退出又唯一绑定于 `bootFinished()` 设置的 `service.bootanim.exit=1`，动画永不停即意味着 `bootFinished()` 从未被调用（[BootAnimation.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/cmds/bootanimation/BootAnimation.cpp)）。这条推理把搜索空间从整条启动链压缩到 userspace 服务层，也决定了后续每一章的任务形态：不是提出猜测，而是宣布某一层可以排除，并把剩余候选按"何时被强制"排序。

五章依次完成这一收敛：界定故障域、逐字节复核镜像与模块、比对构建期契约、判定 `/data` 与 `/metadata` 的残留状态、设计最小化实验矩阵。报告不承诺给出已定案的根因——它给出的是一条可复现的排除链，以及这条链末端剩下的那个嫌疑。

---

## 1. 故障域界定：从 bootanim 启动机制反推启动闸门

### 1.1 论点：把「看得见动画」当作一条信息量极高的证据

多数排障叙述把「卡在开机动画」当成一句现象描述。本章主张相反：**动画能否出现在屏幕上，本身就是一组强约束**。bootanim 不是 init 默认拉起的东西，也不是「系统快好了」的装饰，而是一个由 SurfaceFlinger 显式点名启动、由 SurfaceFlinger 显式请求退出的一次性服务。因此「动画能显示」证明了一整条链路已经打通，「动画永不停」则把故障精确压缩到 `bootFinished()` 这一个从未被调用的函数上。

### 1.2 论据一：bootanim 是「没人点名就不会跑」的服务

AOSP 的 [bootanim.rc](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/cmds/bootanimation/bootanim.rc) 全文只有一个服务块：

```
service bootanim /system/bin/bootanimation
    class core animation
    user graphics
    group graphics audio
    disabled
    oneshot
    ioprio rt 0
    task_profiles MaxPerformance
```

四个选项各有含义（见 [init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md)）：`disabled` 意味着「该服务不会随其 class 自动启动，必须按名字或接口名显式启动」；`oneshot` 意味着「退出后不再重启」。`animation` 这个 class 本身也有明确设计意图，源码文档写道：「animation class 应包含开机动画与关机动画所需的全部服务；由于这些服务可能在启动极早期拉起、并运行到关机最后阶段，`/data` 分区的可用性不被保证。」

**事实**：`class core animation` + `disabled` 的组合意味着 `class_start core` / `class_start animation` 都不会启动它。**推断**：bootanim 出现在屏幕上，前提是有人用控制消息显式点名。

### 1.3 论据二：拉起者是 SurfaceFlinger，不是 init

点名者就在 SurfaceFlinger 里（[SurfaceFlinger.cpp @ lineage-24.0](https://raw.githubusercontent.com/LineageOS/android_frameworks_native/lineage-24.0/services/surfaceflinger/SurfaceFlinger.cpp)）：

```cpp
void SurfaceFlinger::initBootProperties() {
    property_set("service.sf.present_timestamp", mHasReliablePresentFences ? "1" : "0");
    if (base::GetBoolProperty("debug.sf.boot_animation"s, true) &&
        (base::GetIntProperty("debug.sf.nobootanimation"s, 0) == 0)) {
        property_set("service.bootanim.exit", "0");
        property_set("service.bootanim.progress", "0");
        property_set("ctl.start", "bootanim");
    }
}
```

`ctl.start` 的语义由 init 文档定义（[init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md)）：「`SetProperty("ctl.start", "logd")` 将对 logd 执行 `start` 命令」，且这类属性「只能被写、读出时无值」。同一段代码上方的注释还交代了时序：initBootProperties 被 offload 到另一个线程，因为 `property_set` 依赖 `property_service`，而后者「可能被 init 中 `mount_all --late` 之类的慢操作拖住」。

由此形成一组**反向依赖**：动画出现在屏幕上 ⇒ ① init 的 property_service 已可服务 `ctl.*` 控制消息；② SurfaceFlinger 进程存活并完成了初始化；③ SF 作为合成器已能与 display HAL / HWC、gralloc 完成至少一次成功的合成与上屏——因为 bootanim 只是 SF 的一个 client，画面必须经 SF 才能到达屏幕。

**但这组反向依赖的上界可以精确标定**，而不是笼统地说"推不出"：

1. **SF 的启动点是 `on boot`。** AOSP init.rc 全文**无** `class_start animation`、**无** `start surfaceflinger`（`class_start` 的参数只有 `early_hal` / `hal` / `core` / `main` / `late_start` / `charger`），SF 亦非 `disabled`、不提供 `interface`——四条启动路径里三条不适用，剩下唯一一条就是 `on boot` 末尾的 `class_start core`。本机构建 init.rc 同样无 `class_start animation`。
2. **`on boot` 是 `late-init` 的最后一环**，且 `trigger` 是"把后继 action 追加到同一条队列尾部"（init 文档）。故**动画在播 ⇒ `on boot` 已执行 ⇒ `late-init` 的 11 个 trigger 已全部执行**。
3. **但"trigger 已执行"≠"每一步都成功"**——这是必须小心的分界，因为 init 对两类失败的处理语义完全不同：`wait_for_prop` 经 init 主循环停住**整个动作队列**（未满足则队列不前进，机制见 1.6）；而 `mount_all` 失败**不中止队列**（`do_mount_all` 仅在 `FS_MGR_MNTALL_DEV_NEEDS_RECOVERY` 时进 recovery，`FS_MGR_MNTALL_FAIL` 落到 `return Error()`，`Action::ExecuteCommand()` 只记日志、`ExecuteAllCommands()` 继续执行后续命令）。

于是上界可精确表述为：**能阻塞队列的闸门已被排除，不能阻塞队列的失败仍相容。**

- **可排除（阻塞型闸门）**：apexd（`wait_for_prop apexd.status activated`）、odsign（`wait_for_prop odsign.verification.done 1`）、KeyMint **不可达**导致的 `mount_all` 死锁。前两者经 `wait_for_prop` 停住队列；后者有两条独立阻塞路径——`mount_all` 期间 init 等待 `vdc` 返回，不返回则队列原地不动；且若设备 rc 含 `exec_start wait_for_keymaster`，`exec_start` 与 `wait_for_prop` 落在主循环同一个 `||` 分支上，同样不前进。**故「动画在播」这一事实本身就排除 KeyMint 不可达形态**——这是 1.3 链条给第 4 章形态①的直接判据，不是旁证。
- **不可排除（非阻塞失败型）**：`/data` 挂载失败——它返回 `FS_MGR_MNTALL_FAIL` 但队列照常推进，于是出现"动画照播、zygote / system_server 因无 `/data` 起不来"的形态。**这正是"卡动画"而非"bootloop"的机制解释**（详见「待完善事项」第 1 条）。

**KeyMint 必须拆成两形态，不可合并**：① KeyMint **不可达**（未就绪）→ 按官方文档路径死锁 → init 卡住 → 无动画，**已排除**；② KeyMint **可达但解不开原厂那份 key blob**（key blob version binding 失效）→ vold 解密失败 → `mount_all` 返回 FAIL → **不阻塞**，init 继续 → `on boot` 到达 → 动画照播，**未排除**。因此「动画在播」只证明了 KeyMint **已就绪**，**没有**证明它能解开这份 `/data`——第 4 章的首要假设正落在形态 ②。

附带一条独立佐证：按 [Metadata encryption](https://source.android.com/docs/security/features/encryption/metadata)，`mount_all` 期间 property 读写会**阻塞到 `mount_all` 返回**；因此一次**完成返回**的 `property_set` 本身就反证 init 已离开 `mount_all`——这与上面的分界同向，不矛盾。

### 1.4 论据三：退出者是 `bootFinished()`，其调用方在 system_server 侧（推断）

同一个 [SurfaceFlinger.cpp](https://raw.githubusercontent.com/LineageOS/android_frameworks_native/lineage-24.0/services/surfaceflinger/SurfaceFlinger.cpp) 里的 `bootFinished()` 显示：先 `waitForService("window")` 并 `linkToDeath`，然后才 `property_set("service.bootanim.exit", "1")`，注释说明「formerly we would just kill the process, but we now ask it to exit so it can choose where to stop the animation」。该方法是 [ISurfaceComposer](https://raw.githubusercontent.com/LineageOS/android_frameworks_native/lineage-24.0/libs/gui/aidl/android/gui/ISurfaceComposer.aidl) 的 binder 接口，注释为「Signal that we're done booting. Requires ACCESS_SURFACE_FLINGER permission」。至于「谁调用它」，源码此处并未点明，**依据 `waitForService("window")` 这一前置时序推断调用方为 system_server（WindowManagerService 完成启动后回调）——此为推断，非实证**。

消费端在 bootanim 自己身上（[BootAnimation.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/cmds/bootanimation/BootAnimation.cpp)）：`checkExit()` 用 `property_get("service.bootanim.exit", value, "0")` 取值，非 0 才 `requestExit()`；内置 logo 走 `do { … } while (!exitPending())` 的无限循环。**事实**：bootanim 的退出条件唯一地绑定在 `service.bootanim.exit` 上，而该属性只被 `initBootProperties()`（置 0）与 `bootFinished()`（置 1）两处写。

**必须写明的前提**：下面的等价链只在「屏幕上是逐帧推进的循环动画」这一前提下成立。本项目观察到的正是动画持续循环播放、帧在推进（而非定格画面），说明 bootanim 进程存活且主循环在跑。若 bootanim 画出一帧后即崩溃或被 SIGKILL，屏幕同样表现为「停在动画」，但此时 `service.bootanim.exit` 与 `bootFinished()` 就不再是唯一解释，等价链失效——所以本节把它表述为条件命题而非无条件等价。

**条件命题（前提成立时）**：画面停在动画 ⟺ `service.bootanim.exit` 从未被置 1 ⟺ `bootFinished()` 从未被调用。由此只有两类可能：

- **A 类**：system_server 存活，但启动完成路径没有走完（某服务初始化阻塞、HAL 等待超时、avc 拒绝、/data 未就绪等），因而无人调用 `bootFinished()`；
- **B 类**：system_server 起来又死、反复重启，而 SurfaceFlinger 存活，动画照播。BootAnimation.cpp 的 `binderDied()` 只在 **SF** 死亡时 `kill(getpid(), SIGKILL)`，与 system_server 无关；LineageOS 的[调试文档](https://lineageos.org/engineering/HowTo-Debugging/)也指出「系统进程在 adb 起来之前就导致重启」是 ADB 连不上的常见原因。**所以「动画还在播」不等于「system_server 还活着」**。

### 1.5 论据四：AVB 判定的正向证据——能走到用户态即证明 bootloader 侧无硬失败

AOSP 的 [Boot flow](https://source.android.com/docs/security/features/verifiedboot/boot-flow) 用四种可视态向用户传达 Verified Boot 结果，但这四态分属两类，混为一谈是常见误读：

| 可视态 | 触发条件 | 类别 |
|---|---|---|
| YELLOW | LOCKED 且使用自定义信任根 | 锁状态提示 |
| ORANGE | UNLOCKED | 锁状态提示 |
| RED (eio) | dm-verity 发现数据损坏 | 校验失败 |
| RED (No valid OS found) | 找不到可启动系统 | 校验失败 |

**只有 RED 两态是校验失败信号**；YELLOW/ORANGE 只是告知用户「设备处于非标准信任状态」，系统仍会继续启动。

以「四态一个都没出现」作为 AVB 通过的负证据是错误的，理由有二：其一，本设备 bootloader 已解锁，实测 `ro.boot.verifiedbootstate=orange`，按 AOSP 规范本应处于 ORANGE 态，把 ORANGE 计入「失败态」本身即是概念错误。其二，小米机型在解锁或校验异常时的开机提示由厂商 bootloader 自行渲染，不等同于 AOSP 参考实现的视觉，因此「没看到某块屏幕」既不能证明通过、也不能证明失败。

改用一条更强也更简洁的正向证据：[Use Verified Boot](https://source.android.com/docs/security/features/verifiedboot/verified-boot) 规定 AVB 校验发生在「Android 版本所包含的可执行代码与数据被使用之前」，而 Boot flow 对 `RED (No valid OS found)` 的处置是「设备无法继续启动」。据此，**本项目能进入 Android 用户态、并让 SurfaceFlinger 把开机动画合成上屏，这一事实本身即证明 boot/dtbo/vbmeta 链的签名校验未发生硬失败、A/B slot 被判定为可启动**——若校验失败或 slot 不可启动，根本走不到 kernel handoff，更不会出现动画。

### 1.6 已通过的启动闸门清单

| 闸门 | 支撑证据 | 状态 |
|---|---|---|
| preloader / XBL / ABL | 有第一屏与后续画面 | 通过 |
| AVB 签名与 rollback 校验 | 能进入用户态并显示开机动画（硬失败会 halt 在 bootloader，见 1.5）；解锁状态下 bootloader 提示画面由厂商定制，不作为判据 | 通过 |
| 内核解压与 early init | 能进 Android 用户态 | 通过 |
| first-stage init、vendor_dlkm 加载 | 能到 second-stage | 通过 |
| SELinux 策略加载（enforcing） | 策略加载失败会停在 init 阶段（推断） | 通过（推断） |
| APEX 激活（apexd） | apexd 在启动序列早期启动，逐个 verify→loopback→dm 设备→挂载（[APEX file format](https://source.android.com/docs/core/ota/apex)）（推断） | 通过（推断） |
| servicemanager / hwservicemanager | SF 需要 binder 才能被拉起 | 通过 |
| SurfaceFlinger + display HAL + gralloc | 动画真的在动 | 通过 |
| bootanim 自身 | 画面在播 | 通过 |
| **`bootFinished()` 及其调用方** | **动画永不停** | **失败** |

**为什么 `animation` class 不会让 SurfaceFlinger 提前启动（上表全部分析的承重墙）**：[init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md) 对 `class` 的说明含「these services **can be launched very early during bootup**」与「should work when `/data` is not available」两句，常被读成"SF 可能早于 `class_start core` 启动"。这是误读——**那是对设备维护者的设计约束（不许依赖 `/data`），不是时序声明**。实际启动点由 rc 事实决定：启动一个非 `disabled` 服务只有四条路径（`class_start`、`start <name>`、`ctl.start`、`interface_start`）；SF 非 `disabled`、不提供 `interface`（后两条不适用），init.rc 全文又无 `start surfaceflinger`、无 `class_start animation`（`class_start` 的参数只有 `early_hal` / `hal` / `core` / `main` / `late_start` / `charger`），故只剩 `on boot` 末尾的 `class_start core`。设备树侧另经穷举：`device-trees/*/` 全部 8 个 rc 文件中只有 `init.recovery.qcom.rc` 含 `class_start early_hal`。**方法论要点：「服务属于某 class」是设计属性，「该 class 在本构建里被何时 `class_start`」是 rc 事实；排除性论证只能落在后者。**

**可证伪条件（必须保留）**：若设备或厂商 rc（`vendor/etc/init/hw/init.*.rc`、`odm/etc/init/*.rc`）中存在 `class_start animation` 或 `start surfaceflinger`，则 1.3 的链条失效，本章结论须重新评估。核查命令：`grep -rE 'class_start animation|start surfaceflinger' /system/etc/init /vendor/etc/init /odm/etc/init`。本项目设备树派生自社区 TWRP 树，这条不是形式主义。

**证据强度分级**（便于审稿区分哪一段可被质疑）：SF 属 `class core` + `class_start core` 唯一 + init.rc 穷举无替代路径 = **强**（源码可查证）；`mount_all` 失败不中止队列（`do_mount_all` → `queue_fs_event` 的返回码分支、`fs_mgr.cpp`）= **强**；「`mount_all` 期间 init 阻塞、属性读写阻塞至 `mount_all` 返回」= **中**（Metadata 文档的规范性陈述，非本机实测）；「animation class 规范允许早启动」= **反向但弱**（设计许可，非本机配置）。

**`wait_for_prop` 的阻塞性：机制已逐行定位**（原先标注的「实现位置无法定位」已由 `init.cpp` 主循环闭合）。在 `aosp-mirror/platform_system_core` 快照中，[action.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/action.cpp) 的 `Action::ExecuteCommand()` 只做 `InvokeFunc` + 计时日志，**没有任何等待/挂起机制**；`action_manager.cpp` 的 `ExecuteOneCommand()` 与 `property_service.cpp` 也都不含 `waiting_for_prop_` / `start_waiting_for_property` 的定义。**但队列如何被停住，不在这三个文件里——它在 init 主循环**：

```cpp
if (!(prop_waiter_state.MightBeWaiting() || Service::is_exec_service_running())) {
    am.ExecuteOneCommand();
}
```

`MightBeWaiting()` 为真时 `am.ExecuteOneCommand()` **根本不调用**，队列停在这里。配套机制：`PropWaiterState::StartWaiting()` 只记录待等属性并起计时器、**本身不阻塞**；属性变化由属性线程经 `PropertyChanged()` → `CheckAndResetWait()` 匹配后用 **eventfd** 唤醒主线程（[init.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/init.cpp)）。源码注释还记录了旧方案"waited on property changes with a blocking socket … **it was easy to fill that socket and deadlock the system**"，说明这套唤醒机制正是为替代阻塞 socket 而设计——**它的存在本身反证了等待期间主循环确实停住**。

**另有两条结构证据佐证**：① [builtins.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/builtins.cpp) 的 `do_load_persist_props()` 先 `SendLoadPersistentPropertiesMessage()`（交给另一线程加载），再 `start_waiting_for_property("ro.persistent_properties.ready", "true")`——这是一个**自指等待**（init 等待 init 自己加载的属性）；若该等待会冻结 init 服务属性写入的能力，AOSP 每次开机都会死锁，而它并未死锁。② `do_wait_for_prop()` 中的错误串 `"already waiting for a property"` 证明同一时刻只允许一个等待者，说明这是**全局状态**而非某条命令的局部阻塞。由此可安全推出：`wait_for_prop` 停住的是**动作队列**，不是 init 的属性服务——这正是它不会死锁、而 apexd/odsign 仍能置位的原因。

**first stage 不可能是故障点（源码级依据，与第 2 章联动）**：第 2 章的 fstab 比对显示，本项目与原厂的差异只落在 `nofail` 条目（mi_ext / overlay）上。而 [fs_mgr.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/fs_mgr.cpp) 的 `fs_mgr_mount_all()` 对 `no_fail` 条目的挂载失败只打印 `"Ignoring failure to mount an un-encryptable, interrupted, or wiped partition on %s at %s options: %s"` 后 `continue`，**不执行 `++error_count`**；函数末尾仅以 `if (error_count) return FS_MGR_MNTALL_FAIL;` 判定失败。因此 fstab 的这处差异**在原理上无法把 `mount_all` 判为失败**，「故障发生在 first stage 之后」由此成为源码级结论而非推测。

**精确边界**：上述忽略分支的前提是 `mount_errno != EBUSY && mount_errno != EACCES && !encryption_interrupted && !should_use_metadata_encryption(...)`；metadata 加密是**另一条互斥分支，根本不检查 `no_fail`**，其 `error_count` 只由 `call_vdc` 的成败决定（即交给 vdc 重试，而非直接阻断）。本项目 fstab 差异不涉及 `/data` 条目，故不受此边界影响。

**关于 `/data/misc/bootanim` 这条动态锚，只能单向使用**（依据：[init.rc](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc) 的 `on post-fs-data` 段先依次执行 `chown/chmod /data`、`restorecon /data`、`installkey /data`，段落后半部才 `mkdir /data/misc/bootanim 0755 system system`，且该行位于 `restart apexd` → `wait_for_prop apexd.status activated` → `perform_apex_config` 之后）：

- **缺失是强判据**：目录不存在 ⇒ 这份 `/data` 上从未有任何一次启动走完 `on post-fs-data` 到该行 ⇒ **apexd 从未成功激活到 activated**。
- **存在是弱判据**：`/data` 是持久分区、`mkdir` 对已存在目录幂等，本机在刷 LOS 前运行原厂 A17 并正常开机时就已创建过该目录，故其存在对本次启动几乎无信息量，仅在「刷入前 wipe 过 `/data`」的前提下可作参考。
- **不可用目录元数据充当「逐次启动水位线」**：[builtins.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/builtins.cpp) 的 `make_dir_with_options()` 对已存在目录只在 mode 或 uid/gid 不匹配时才调用 `lchown` / `fchmodat`；而 `0755 system system` 恰好匹配，两个系统调用都不执行，**mtime 与 ctime 均不更新**，始终停在最初创建那一刻。要重建启动时间轴，须改用其他信号（见第 5 章）。

### 1.7 七类根因谱系：为什么全部落在 userspace

| 根因类别 | 机制要点 | 典型第一现场 | 状态（以 1.6 链条成立为前提） |
|---|---|---|---|
| system_server 崩溃/重启循环（B 类）或启动路径 hang（A 类） | B 类：SF 存活故动画照播；A 类：无人调用 `bootFinished()` | `logcat -b crash`、`/data/tombstones`、`dumpsys` | **主候选（两形态并存）** |
| HAL 与 VINTF | device manifest 描述「提供什么」，framework compatibility matrix 描述「要求什么」，二者需对账（[VINTF](https://source.android.com/docs/core/architecture/vintf)）；缺失/不匹配的 HAL 会让系统服务在 `waitForService` 上挂住 | servicemanager 列表、`dumpsys` 不可用时看 init | **保留（收窄）**：`class_start hal` 只是 fork、不阻塞，故 hal class 已被拉起不等于注册成功；唯一例外是 composer HAL——SF 既然在合成帧，这条链必然通 |
| SELinux avc denied | [AOSP 文档](https://source.android.com/docs/security/features/selinux) 明确警告：**更新的平台策略 + 更旧的 vendor 策略**会产生兼容性问题——本项目正是 A17 平台 + A16 vendor 树 | `dmesg` 的 avc 行 | **保留** |
| data 加密与 vold | 分两层：`/data` **挂载**失败返回 `FS_MGR_MNTALL_FAIL` 但不阻塞队列，与动画在播相容；FBE **凭据解密**走 `on nonencrypted` → `class_start main` / `late_start`，该触发链不在 `late-init` 序列内 | init/vold 日志 | **保留（仅挂载失败与解密两层）** |
| zygote 与 odsign | [rootdir/init.rc](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc) 的 `on zygote-start` 段首行为 `wait_for_prop odsign.verification.done 1`，其后才 `exec_start update_verifier` 与 `start zygote` | init 日志、odsign 状态 | **条件性排除**：`wait_for_prop` 同步阻塞，动画在播即证明该等待已放行。注意排除的是"未完成"形态，不是"校验失败"形态 |
| APEX 状态 | apexd 校验或激活失败会缺模块（[APEX file format](https://source.android.com/docs/core/ota/apex)）；`wait_for_prop apexd.status activated` 同样同步阻塞 | init 日志、`/apex` | **条件性排除（阻塞形态）**：但 `apexd.cpp` 的 `OnAllPackagesActivated()` 无条件置 `activated`，故"闸门放行"不证明"激活成功" |
| nofail 挂载 / mount_all --late 慢 | `mount_all` 执行点在 `late-fs`，早于 `on boot`；SF 源码注释中的 "delayed" 指单线程争用，不是并发 | init 日志时序 | **排除**（且"慢"≠"卡"） |

**为什么都属于 userspace**：这些类别都不改变内核二进制，也不改变 AVB 判定，它们的共同前置是「内核已把控制权交给 init、init 已把控制权交给 zygote/system_server」。**其中 odsign / apexd 两项的排除依赖 1.6 的链条**——若 1.6 的可证伪条件被触发（设备侧 rc 存在 `class_start animation` 或 `start surfaceflinger`），这两行须退回候选。

### 1.8 结合本项目实测事实的判读

1. **内核二进制与原厂 A17 逐字节相同** → 直接排除内核本体、defconfig、驱动差异。
2. **`--disable-verification` 对 vbmeta 与 vbmeta_system 都无效，符合预期**：该操作只影响 bootloader 侧对分区的校验与 `androidboot.veritymode` 一类的内核参数，而卡动画发生在 AVB 判定之后很久，它不可能改变用户态行为。此项失败不构成新信息。
3. **ramoops 链路完整但 pstore 为空**：ramoops 记录的是内核 oops/panic 时的 dmesg。若故障是用户态 hang 而非内核崩溃，`kmsg_dump` 不会触发，读出为空是**预期**。**但该推论有严格前提**：pstore 内容只在 warm reset（复位不丢失 DRAM 内容）后仍可读；本项目 ramoops 节点**无 ECC**，而内核文档指出 ECC 的作用正是硬件复位后恢复受损 RAM 内容。因此若既往复现用的是长按电源冷复位，「pstore 为空」只能说明**没捞到**，不能说明**没发生**。此点留待第 5 章 5.1 按同一口径展开。
4. **原厂 A17 的 vendor build.prop 仍写 `ro.vendor.build.version.release=16`** → vendor 属性未随平台升级，说明「用属性判断 vendor 版本」在本机型上不可靠。

### 1.9 小结

「能看到动画」把故障域从「整个启动栈」压缩到「first stage 之后的 userspace 服务层」；「动画永不停」进一步把它压缩到「`bootFinished()` 的调用方」。需要强调：**「卡在开机动画」不等于「系统完全没起来」**——bootanim 是独立进程，它自己卡住时 SurfaceFlinger 与 system_server 可能仍在运行，故本报告的结论是「启动完成信号未发出」，而非「系统未启动」；第 5 章的 E7 实验（将 bootanim 置为 disabled）正是为分离这两种情形而设计。后四章的所有搜索都应当在这个空间内进行，且必须优先区分 A 类（hang）与 B 类（crash loop）。

---

## 2. 镜像与模块层静态复核：boot/vendor_boot 结构与 GKI module_layout CRC

### 2.1 论点：本章的产出是判据，不是根因

本章从镜像结构与内核模块加载逻辑两个方向做静态复核，目标是一次性钉死「启动链本体（kernel / boot / vendor_boot / init_boot / recovery）有问题」这一类假设。本章的产出不是根因，而是一张「哪些层已经可以宣布排除」的判据表。

### 2.2 boot header v4 与 vendor_boot 的五段结构

boot 与 vendor_boot 的头部格式由 `system/tools/mkbootimg/include/bootimg/bootimg.h` 定义（[bootimg.h（android17-release）](https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/android17-release/include/bootimg/bootimg.h)），字段语义见 [Boot image header](https://source.android.com/docs/core/architecture/bootloader/boot-image-header)。本项目 boot.img 与 vendor_boot.img 均为 header v4。

boot header v4 的字段很精简：`kernel_size`、`ramdisk_size`、`header_size`（v4 定长 1584 字节，其中 1536 字节留给 cmdline），v4 相对 v3 只新增 `signature_size` 一个字段，用于记录 boot.img 签名段的长度。本项目 boot.img 的 `signature_size` 实测为 0，即镜像未附签名段。从 v3 起头部不再携带 `kernel_addr` / `ramdisk_addr` / `tags_addr`，加载地址移入 vendor_boot。

vendor_boot 在 v4 下由五段构成（[Vendor boot partitions](https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions)）：① 头部；② vendor ramdisk（可由多片拼接，v4 起支持）；③ dtb；④ vendor ramdisk table（v4 新增，描述每个 ramdisk 片段的类型与加载地址）；⑤ bootconfig（v4 新增）。后两段是 v4 相对 v3 的增量，也是「bootconfig 能被 bootloader 传进内核」的结构基础。

把 LOS 产物与原厂 A17 的同名镜像逐段解开对比：

| 项 | 原厂 A17 | LOS 24 | 判据 |
|---|---|---|---|
| boot 内核 | 41,511,424 B / `ed9e27aa…` | 同 | **逐字节相同** |
| boot 结构 | kernel 41.5 MB / ramdisk 0 | 同 | 结构一致 |
| vendor_boot ramdisk | 468 文件 / 461 个 .ko | 468 / 461 | 清单完全一致 |
| vendor_boot dtb | 6,557,139 B | 6,557,139 B | 一致 |
| recovery.img | kernel_size=0 / ramdisk 28,361,524 B | kernel_size=0 / ramdisk 18,952,705 B | 结构一致（ramdisk 段差 9,408,819 字节，系**原厂 recovery 与 LOS recovery 的内容差异**——两者装载的 recovery 程序本就不同，不构成结构差异；TWRP 为另一独立镜像，ramdisk 54,962,650 B，不在此对比内） |

vendor_boot ramdisk 体积差 3.7 MB（22.1 vs 18.5）只是 lz4 压缩率不同，解包后文件数与模块清单完全一致。结构层没有任何可指摘的差异。

### 2.3 init_boot 的同源约束及其反向推论

init_boot 承载的是 GKI 通用 ramdisk，其职责边界见 [Generic boot partition](https://source.android.com/docs/core/architecture/partitions/generic-boot)。通用 ramdisk 的内容被刻意压到最小：只含 first stage `init` 和一个带时间戳的属性文件，其文件清单由 `generic_ramdisk.mk` 白名单约束（同上）。**由此可知**，init_boot 的载荷是由 system 树构建出来的，它与 `/system` 同源是构造结果，而非一份独立约定——这是从构建方式推出的判断，不是文档里的逐字要求。

实测印证了这个形态：LOS 的 init_boot ramdisk 共 5 个文件，比原厂多一个 `first_stage_ramdisk/` 目录，属于 GKI 通用 ramdisk 的正常形态。

由此得到一个反向推论：一旦 init_boot 混入旧版 `init` / `first_stage_init` 或其依赖库，故障表现会是**根本没有开机动画**（黑屏、panic，或 bootloader 超时回退），而不是停在动画上。本项目有两条**独立**证据指向「内核与 first stage 均无问题」：

1. 设备能稳定显示 LOS 的开机动画——说明 first stage 已成功、`/system` 已挂载、second stage 已接管；
2. TWRP 能正常启动——TWRP 的 recovery.img 是 `kernel_size=0` 的纯 ramdisk，内核取自 boot 分区，它不依赖 LOS 的 init_boot 就能跑完自己的 init。

两条证据机制不同、互不依赖，共同把「内核不可执行 / first stage 起不来」这一类假设排除掉。

### 2.4 bootconfig 的静态校验

vendor_boot 的 bootconfig 段由 bootloader 附在 initrd 尾部（带 magic、size、checksum），内核在 `start_kernel()` 中调用 `setup_boot_config()`，位置在 `setup_arch()` 之后、`setup_command_line()` 之前；解析后 `kernel.*` 键被转成命令行参数拼在 boot cmdline 之前，`init.*` 键追加到 `--` 之后传给用户态 init（[init/main.c（v6.12）](https://raw.githubusercontent.com/torvalds/linux/v6.12/init/main.c)）。语义规范见 [Implement bootconfig](https://source.android.com/docs/core/architecture/bootloader/implementing-bootconfig) 与 [Bootconfig admin guide](https://www.kernel.org/doc/html/latest/admin-guide/bootconfig.html)。

逐项 diff 的结果是 LOS 只缺两项：

```
androidboot.vendor.qspa=true
androidboot.serialconsole=0
```

前者是 vendor QSPA 开关，后者是串口控制台开关。两者都不参与分区挂载、不参与 AVB 校验、不参与模块加载，且 bootconfig 与 `module_layout` CRC 分属完全无关的两条路径（前者是命令行，后者是 ELF 的 `__versions` 段）。判为不足以构成启动闸门。

### 2.5 fstab 三级查找与 nofail 的边界

fstab 的定位有**两层机制，不可混为一条优先级**。① first stage 使用 vendor_boot 里的 `/first_stage_ramdisk/fstab.<ro.hardware>` 覆盖层（AOSP 明确要求设备 fstab 放这里，而非 boot 分区）。② 之后 init 按 `init/README.md` 的规则查找：候选名为 `fstab.${ro.boot.fstab_suffix}` → `fstab.${ro.hardware}` → `fstab.${ro.hardware.platform}`，搜索目录为 **`/odm/etc` → `/vendor/etc` → `/`**（原文 "in that order"）。本机 `ro.hardware=qcom`，对应 `fstab.qcom`。

`nofail` 的语义边界必须说清：它只把「这一条挂载失败」降级为警告。在 `fs_mgr_mount_all()` 里，`no_fail` 为真时不累加 `error_count`，为假时失败即致命（[fs_mgr.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/fs_mgr/fs_mgr.cpp)）。因此判断 fstab 差异是否有害，不能看「有没有差异」，要看差异落在哪一类条目上：`system` / `vendor` / `metadata` 这些关键条目一旦失败就是硬失败。

按这个标准复核，LOS 与原厂的 fstab 差异仅落在 `mi_ext`、overlay 等带 `nofail` 的条目上；`system` / `vendor` 的挂载参数（含 `avb=vbmeta_system`）一致。这一层可以排除。

### 2.6 本章核心：GKI 模块匹配的判定顺序

内核开了 `CONFIG_MODVERSIONS`，`struct module` 的 layout CRC 就是模块加载的第一道闸门。判定顺序决定了「CRC 先于 vermagic」这个论点能否成立，因此必须落到源码。

**前提必须写全**：下述判定以**三个前提同时成立**为前提——① 内核侧 `CONFIG_MODVERSIONS=y`（决定 `check_version()` 是真检查还是桩函数、`same_magic()` 是否跳过版本前缀）；② 模块侧该 `.ko` 自带 `__versions` 段（`same_magic()` 的第三参传的是 `info->index.vers`，模块构建时若未开 MODVERSIONS 就没有该段，`has_crcs=false`，照样退回整串比较）；③ 实现前提——本条建立在 v6.12 的实现之上，`same_magic()` 的前缀跳过规则、`check_modstruct_version()` / `check_version()` 的调用位置与返回码若在未来内核版本中改写，**相关结论**需重核。**本项目①②均满足**：内核 vermagic 后缀含 `modversions`，A16/A17 模块均带 `__versions` 段。若内核未开 `CONFIG_MODVERSIONS`，`version.c` 的 `#else` 分支里 `check_version()` 是 `return 1` 的桩函数、`same_magic()` 退化为整串 `strcmp`，闸门会回到 vermagic 的版本前缀上——**本节结论不适用于该配置**。

**失效范围需划准**：「`module_layout` 的 CRC 是闸门」属于 `CONFIG_MODVERSIONS` 的**机制契约**，不因上述函数实现改写而失效；「闸门排在 vermagic 之前」「vermagic 前缀被跳过」属于**实现事实**，会随实现变化。把前者一并标成"可能失效"是过度自我削弱，与把后者说成永久成立同样不准确。

`early_mod_check()` 的实际调用顺序（[kernel/module/main.c（v6.12）](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/module/main.c)）：

```c
static int early_mod_check(struct load_info *info, int flags)
{
	int err;

	/* Now that we know we have the correct module name, check
	 * if it's blacklisted. */
	if (blacklisted(info->name)) {
		pr_err("Module %s is blacklisted\n", info->name);
		return -EPERM;
	}

	err = rewrite_section_headers(info, flags);
	if (err)
		return err;

	/* Check module struct version now, before we try to use module. */
	if (!check_modstruct_version(info, info->mod))
		return -ENOEXEC;

	err = check_modinfo(info->mod, info, flags);
	if (err)
		return err;

	mutex_lock(&module_mutex);
	err = module_patient_check_exists(info->mod->name, FAIL_DUP_MOD_BECOMING);
	mutex_unlock(&module_mutex);

	return err;
}
```

（以上为 v6.12 `kernel/module/main.c` 的**逐字引用，未改写任何一行，也未插入任何标记**。特别注意原文注释 "Check module struct version **now, before we try to use module**"——内核作者自己就写明了这个校验必须先于模块被使用，这是"CRC 先于 vermagic"最直接的证据，不需要本报告另加注解。）

即：**黑名单 → `rewrite_section_headers()` → `check_modstruct_version()`（CRC）→ `check_modinfo()`（vermagic）→ 重复模块检查**。黑名单由 `blacklisted()` 在函数第一步直接完成，并不在 `check_modinfo()` 内部；`check_modinfo()` 体内只有 `get_modinfo("vermagic")`、`try_to_force_load()` / `same_magic()` 与 `check_modinfo_livepatch()` 三件事。这一顺序在 v6.12、v6.12.69、v6.17 三处源码上逐一核对过，形态一致。

**这条顺序就是本章论点的源码级依据**：CRC 校验（③）排在 vermagic 校验（④）之前，意味着 CRC 不匹配的模块根本走不到 vermagic 比较那一步。反过来说，`module_layout` 的 CRC 是**第一道闸门**（整体结构体 ABI 的粗粒度校验）；`early_mod_check()` 返回后还有一条更细的路径——`simplify_symbols()` 解析未定义符号时经 `resolve_symbol()` 调用 `check_version()`，失败使符号解析返回 `-EINVAL`，逐符号 CRC 也是闸门，只是排在后面、粒度更细。

再看 `same_magic()`：`has_crcs` 为真时，比较前会把两侧指针都推过第一个空格，即**跳过 release 段**（[kernel/module/version.c（v6.12）](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/module/version.c)）：

```c
/* First part is kernel version, which we ignore if module has crcs. */
int same_magic(const char *amagic, const char *bmagic, bool has_crcs)
{
	if (has_crcs) {
		amagic += strcspn(amagic, " ");
		bmagic += strcspn(bmagic, " ");
	}
	return strcmp(amagic, bmagic) == 0;
}
```

实测证据来自**原厂 A16 基线**（不是本项目当前构建）：原厂 A16 的 `vendor_boot` ramdisk 里 416 个模块，vermagic 为 `6.12.23-android16-5-gd8653a69a3aa-mi-4k`，而同一代原厂 boot 内核为 `6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k`——**release 段与构建标记都不同**，而原厂系统在该组合下正常启动。这说明「release 串必须逐字相同」是错的；必须对齐的是 KMI generation 与符号 CRC（[Kernel module support](https://source.android.com/docs/core/architecture/kernel/kernel-module-support)、[Building External Modules](https://docs.kernel.org/kbuild/modules.html)）。

> 口径说明：本项目当前设备已是 A17 内核 `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`。上述 A16 数据用于说明"release 段不同不影响加载"这一机制，**不能**读作"本项目构建正常"——本报告的前提正是设备卡在开机动画。

**四级诊断表（现场可用，按实际执行顺序排列）**：

| 命中层 | 日志 | 返回码 |
|---|---|---|
| 黑名单（`early_mod_check()` 首步，`blacklisted()`） | `Module %s is blacklisted` | `-EPERM` |
| `module_layout` CRC（`check_modstruct_version()`） | `disagrees about version of symbol module_layout` | `-ENOEXEC` |
| vermagic（`check_modinfo()`） | `version magic '%s' should be '%s'` | `-ENOEXEC` |
| 逐符号 CRC（`resolve_symbol()`，经 `simplify_symbols()` 间接调用，在 `early_mod_check()` 之后） | 两行：`disagrees about version of symbol <其他符号名>`，随后 `Unknown symbol <名> (err -22)` | `-EINVAL` |

**关键提示**：`module_layout` CRC 与逐符号 CRC **日志文本完全相同**（都是 `disagrees about version of symbol`），只能靠**符号名 + errno** 区分——出现 `module_layout` 且 `-ENOEXEC` 是结构体布局级不匹配，出现别的符号名且 `-EINVAL` 是个别符号 ABI 漂移。只看日志不看 errno 会误判。另有一个可用的旁证：**逐符号 CRC 失败会打印两行**（`disagrees…` 后紧跟 `Unknown symbol … (err -22)`），而 `module_layout` 那一支不经过符号解析，只有一行——两行是否成对出现，可用来确认命中的是哪一层。

据此形成**四步静态验证法**：

1. 逐个 `.ko` 抽 `vermagic`，统计 release 段与 KMI generation 的分布；
2. 比对模块 `__versions` 与内核 `__crc_<symbol>`（可用 `modinfo`、`modprobe --dry-run` 交叉验证，[modprobe(8)](https://manpages.debian.org/testing/kmod/modprobe.8.en.html)）；
3. 核对 `system_dlkm/lib/modules/` 的版本目录名是否等于目标内核的 `uname -r`；
4. 核对 `modules.load` 与磁盘 `.ko` 一一对应，且旧代模块计数必须为 0。

### 2.7 踩坑复盘

**坑一：只刷 boot 不刷 vendor_dlkm。** `vendor_dlkm` / `system_dlkm` 在这台机器上是 super 内的逻辑分区，bootloader 模式的 fastboot 看不到，必须先进 fastbootd。只刷 `boot`（A17 内核 6.12.69）而模块留在 A16（6.12.23），结果是 A17 内核 + A16 模块，KMI 不匹配、模块一律拒绝加载，卡在小米第一屏，连 TWRP 都进不去——这是本项目唯一一次把 CRC 假设**实证**出来的场景。

**坑二：镜像不原子。** kernel / vendor_dlkm / system_dlkm / vendor_ramdisk 必须整体替换，任何一次「只换一半」都会重新制造一个假故障。

**坑三：stale 暂存目录静默污染产物。** 本项目构建产物曾混入 A16 模块——`vendor_dlkm` 402 个中 366 个、`vendor_ramdisk` 461 个中 405 个是 6.12.23 版本，原因是 `out/target/product/pandora/` 下的模块暂存目录是早期构建残留，而构建按路径取文件、对内容无语义校验，只要文件存在就打包。单看「461 个 .ko，清单与原厂一致」毫无异常，只有按 vermagic 分组计数才暴露 405/461 这个异常比例。清理暂存并重建后，A16 计数归零。

**边界：CRC 复核的价值与它解释不了的东西。** 清理 stale 模块、重新构建后，产物中 A16 模块计数归零，但设备仍未进入系统。这说明模块污染是「曾经存在的真实缺陷」，却不是「卡动画的原因」。CRC 复核的真正价值在于**排除法与防污染**：它把「模块不匹配」这个高频干扰项一次性钉死，避免后续调查被反复拉回镜像层；但它不能解释当前症状。据此必须明确本章的结论边界——**本章完成的是「宣布某一层可以排除」，不是「找到根因」**。

### 2.8 小结：三层可宣布排除的判据

| 层 | 判据 | 结论 |
|---|---|---|
| 镜像结构 | boot / vendor_boot / init_boot / recovery 四者结构与原厂同构，vendor_boot ramdisk 文件清单与 461 个 .ko 逐项一致 | 可排除 |
| 内核本体 | boot 内核 sha256 与原厂一致；TWRP 纯 ramdisk 可启动 | 可排除 |
| 模块匹配 | `early_mod_check()` 顺序确认 CRC 先于 vermagic；四步静态验证法确认产物中旧代模块计数为 0 | 可排除（且不再复发） |

三层排除之后，故障域被压缩到 **second stage init 的挂载及之后阶段**。此处须明确边界：第 2 章只证到「`/system` 已挂载、first stage 所需模块已通过 CRC + vermagic」，**不含** `/data` 的 `mount_all --late` 与 `/metadata` 相关路径——这两处分别由第 4 章与第 5 章处理。不可写作"init 之后的用户态"：`/data` 挂载就发生在 init 内部，那样写会把尚未排除的域误标为已排除。

---

## 3. 构建期契约缺口：A16 设备树与 A17 framework/blobs 的 VINTF、sepolicy、VNDK 比对

### 3.1 论点：契约缺口按"何时被强制"分三档

A16 设备树与 A17 系统之间的分歧不是"代码写错了"，而是**契约代际错配**。Treble 把原本隐含的耦合逐条显式化为可验证契约（KMI / VINTF / HAL 接口 / SELinux），每类契约有各自的强制时机（[Android Vendor 升级要跨过的四道墙](https://alanhc.github.io/til/docs/til-android-vendor-upgrade)）。本章提出一个贯穿全章的统一判据：**契约缺口按"何时被强制"分为三档——构建期、first stage init、system_server**。本项目已越过前两档（能构建、能点亮、动画在播），因此剩余缺口在逻辑上必然落在第三档，其症状形态只能是 avc denied、dlopen failed、HAL 服务缺失、服务初始化超时，而不可能是 init panic。

### 3.2 VINTF：声明层契约，提供证据链而非因果

VINTF 是"manifest 声明我提供什么 / compatibility matrix 声明我要求什么"的四件套双向匹配机制。设备清单位于 `/vendor/etc/vintf/manifest.xml` 与 `/odm/etc/vintf/manifest.xml`（含 `_SKU` 变体与构建期 `vintf_fragments` 合并）；framework 侧兼容矩阵由 system、system_ext、product 三份 FCM 在运行期拼接（[Vendor interface object](https://source.android.com/docs/core/architecture/vintf/objects)、[Compatibility matrixes](https://source.android.com/docs/core/architecture/vintf/comp-matrices)）。匹配规则是硬性的：`manifest.target-level` 必须**完全等于** `compatibility-matrix.level`；同级 `<hal>` 之间是 AND 关系；版本区间只作下限语义（[Matching rules](https://source.android.com/docs/core/architecture/vintf/match-rules)）。FCM 按 YYYYMM 编号，官方对照表明确到 202404 对应 Android 15、202504 对应 Android 16（[FCM 生命周期](https://source.android.com/docs/core/architecture/vintf/fcm)）；按同一编号规律可推得 A17 世代应为 202604，但 **A17 的正式对应值仍以官方对照表为准**，本文不把该外推当事实使用。

这里藏着一个真实的 A16→A17 契约变更：`<hal optional="true">` 在 Android 15 之后被废弃，**不再有任何效果**，若某 HAL 必须存在只能在测试中强制（[Compatibility matrixes](https://source.android.com/docs/core/architecture/vintf/comp-matrices)）。A16 时代设备树若用 optional 表达"这个 HAL 可以没有"，在 A17 上这句声明被静默作废，所有 HAL 一律按必需对待——不报构建错，只在运行期以"要求存在但不存在"的形式暴露。

**静态比对方法**（离线可完成，四步）：① 解包：`simg2img` + loop mount 挂载 vendor / odm / system 镜像；② 取声明侧：`*/etc/vintf/manifest*.xml`（含 `_SKU` 变体）；③ 取要求侧：`system/etc/vintf/compatibility_matrix.xml`（`level` 为该代 YYYYMM 值）及 system_ext / product 两份；④ 做 diff：抽取 `<fqname>` 与 AIDL 的 `<name>/<version>/<interface>/<instance>` 四元组求集合差，并核对 `manifest.target-level` 与 `ro.board.api_level`（YYYYMM 格式，由构建系统写入 vendor/build.prop，[VTS Test setup](https://source.android.com/docs/core/tests/vts/setup11)）。

但必须强调：**VINTF 本身不阻断 init**。它给出的是"manifest 声称有、servicemanager 里查不到"的证据链；真正让 system_server 卡住的是 HAL 进程根本没起来，而起不来的原因在 sepolicy 域、属性、库路径，不在 XML。

### 3.3 sepolicy 版本化：本章技术核心

平台与 vendor 策略分离构建，public 类型按 `PLATFORM_SEPOLICY_VERSION` 版本化（[Build SELinux](https://source.android.com/docs/security/features/selinux/build)）。vendor 策略里引用的公共类型在编译期被翻译成版本化属性（如 `vendor_init_202504`、`sysfs_202504`），再由各历史版本的 mapping 文件把它们绑到当前平台的真实类型上：`system/sepolicy/private/compat/{ver}/{ver}.cil` 安装为 `/system/etc/selinux/mapping/{ver}.cil`，而新增公共类型必须在该文件里映射到至少一个版本化属性，或在 `{ver}.ignore.cil` 里显式声明"旧版本无对应类型"（[Policy compatibility](https://source.android.com/docs/security/features/selinux/compatibility)）。这就是 `plat_pub_versioned.cil` + mapping 的实质——**跨版本兼容靠映射，不靠版本号相等**。

LineageOS 24 的 compat 清单是 31.0 / 32.0 / 33.0 / 34.0 / 202404 / 202504，genfs 标签版本有 202504 / 202604 / 202704 三档（[Android.bp](https://raw.githubusercontent.com/LineageOS/android_system_sepolicy/lineage-24.0/Android.bp)）。本项目实测：原厂 `plat_sepolicy_vers.txt` 为 **202504**，LOS 构建产物同名文件为 **202704**。原厂的 202504 **正好落在这份 compat 清单内**：A16 设备树写的 vendor 策略在 A17 平台上仍被正式支持，映射机制可以工作。

> 注：lineage-24.0 分支 `system/sepolicy/Android.bp` 的默认 `PLATFORM_SEPOLICY_VERSION` 为 202604，与本项目产物的实测值 202704 **不符**。推测由设备树或构建配置覆盖所致，属值得单独核实的异常；但无论取 202604 还是 202704，原厂 vendor 侧的 202504 都落在 compat 清单内，本章推论不因该口径变化而改变。

加载路径同样关键：`precompiled_sepolicy` 是否被采用，取决于 plat / system_ext / product 三组 `*_sepolicy_and_mapping.sha256` 与 `precompiled_sepolicy.*.sha256` 是否**全部**一致；任一不一致，init 回退到设备端即时编译，**而不是加载失败**（原文：`init` falls back to the on-device compilation path，[Build SELinux](https://source.android.com/docs/security/features/selinux/build)）。而 init 早期序列是 first stage → `selinux_setup`（策略在此编译并加载）→ `second_stage`（[init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md)）。两条合起来得出本章最重要的判据：**sepolicy 版本号不一致几乎不可能造成"卡动画"**——若策略真的加载失败，init 在 `selinux_setup` 阶段就死了，根本轮不到 SurfaceFlinger 起来播动画。

但 sepolicy 仍是 A16 树 + A17 blobs 的最大二级嫌疑，缺口不在"版本号"而在"覆盖范围"：① **域缺失**——A17 blobs 里新增或改名的 HAL 服务在 A16 设备树中没有对应 domain 与 `init_daemon_domain` 规则，服务被错误域启动或直接拒绝启动，依赖它的 framework 服务等不到 binder；② **genfs 标签缺失**——`BOARD_GENFS_LABELS_VERSION` 若停在 202504，A17 新增的 /vendor、/proc 节点无 genfscon 标签，落到默认标签，访问即 avc denied；③ **file_contexts 未覆盖新路径**，新文件统一落到 `vendor_file`；④ **属性名映射缺失**——A17 新增属性若未在设备树 property_contexts 中声明，init `setprop` 被拒，服务静默读不到配置。这四类都不让构建失败，且都在 first stage 之后才发作，与"动画照播"完全吻合。另需警惕：每个新 API level 都在收紧 neverallow，逐条 allow 是掩盖而非修复（[四道墙](https://alanhc.github.io/til/docs/til-android-vendor-upgrade)）。

### 3.4 VNDK 废弃：只会在运行期炸的典型

VNDK 自 Android 15 起废弃：原 VNDK 库改装入 vendor/product 镜像，A15+ 构建的 vendor/product **不再写 `ro.vndk.version` 与 `ro.product.vndk.version`**，VNDK APEX 与 vendor snapshot 一并移除（[VNDK overview](https://source.android.com/docs/core/architecture/vndk)）。含义很直接：A17 上不存在 `/apex/com.android.vndk.vXX` 与 `/system/lib64/vndk-XX` 这套路径。若设备树仍按 A16 时代习惯设置 `BOARD_VNDK_VERSION`，Soong 会按"存在 VNDK"的模型组织 vendor 模块的链接与安装路径，运行期即 `dlopen failed: library "..." not found`，典型表现是 Java 层 `UnsatisfiedLinkError`，出现在 system_server 加载 JNI 库或 HAL 服务启动时（[LineageOS HowTo-Debugging](https://lineageos.org/engineering/HowTo-Debugging/)）。官方给的两种修法是 shim 库与 patchelf（同上）。静态排查点：vendor 分区是否残留 `ro.vndk.version`，blobs 的 DT_NEEDED / RPATH 是否指向 `/system/lib64/vndk-*` 或 `/apex/com.android.vndk.*`。

### 3.5 nofail 挂载：已排除

原厂 fstab 对 `mi_ext` 与一组 overlay 挂载标注 `nofail`（本项目实测），LOS 树里这些条目整体缺失——即 LOS 根本不尝试挂载，而非挂载后失败。`nofail` 的语义已由源码确定：`fs_mgr_mount_all()` 对带 `no_fail` 标志的条目挂载失败时只打印 `Ignoring failure to mount ...`，**不执行 `++error_count`**；函数末尾才 `if (error_count) return FS_MGR_MNTALL_FAIL`（[fs_mgr.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/fs_mgr.cpp)）。而本项目 fstab 与原厂的差异恰好只落在 mi_ext 与 overlay 这两个 nofail 条目上，因此**该类缺口在原理上不可能造成启动失败**。

剩余影响仅在叠加层与配置资源：RRO 未生效时资源解析回退到目标包自身的值，不会崩（[Runtime resource overlays](https://source.android.com/docs/core/runtime/rros)）；privapp-permissions 白名单与 sysconfig 缺失会让特权应用降权或禁用。结论：nofail 类缺口**已排除**，不进入候选根因排序，只记为"资源与配置层面的次要影响"。

### 3.6 判据汇总

| 契约缺口 | 强制时机 | 本项目状态 | 症状形态 |
|---|---|---|---|
| neverallow 冲突 / 构建期 checkvintf / VNDK 快照 | 构建期 | 已通过（构建成功） | 编译报错 |
| system、vendor 挂载失败、AVB 校验、KMI/module_layout | first stage | 已通过（动画已播） | 无动画、init panic、直接重启 |
| SELinux 策略编译或加载失败 | first stage（`selinux_setup`） | 已通过 | 到不了动画 |
| sepolicy 版本号 ≠ 平台版本 | 不强制（回退即时编译） | 存在（原厂 202504 vs LOS 202704） | 无 |
| HAL 域缺失 / genfs 标签缺失 / file_contexts 未覆盖 / 属性未声明 | system_server | **高度可疑** | avc denied、服务起不来 |
| manifest 声明 HAL 但服务未运行（含 optional 失效） | 运行期 checkvintf + 客户端等待 | **高度可疑** | HAL not found、初始化超时 |
| VNDK 缺失 / dlopen 失败 | system_server / HAL 启动 | 可疑 | UnsatisfiedLinkError |
| seccomp 策略缺口（A16 policy vs A17 新 syscall） | system_server（进程被直接杀死） | 未检查 | `SIGSYS` + `SYS_SECCOMP` |
| keymint/keymaster 版本低于 FCM 要求 | `post-fs-data`（`/data` 解密） | 未检查；wipe 后可绕过 | 卡解密 / bootloop，**非**卡动画 |
| nofail 挂载条目缺失（mi_ext、overlay） | 资源解析期 | **已排除**（源码证明 `no_fail` 失败不计入 `error_count`） | 仅叠加层资源缺失 |

本表所列判据第 5 章不再重复，实验设计直接引用本章编号。

上表中三类高可疑缺口在运行期应有各自的可观测信号，可作为后续取证的**预测**：HAL 域缺失表现为 init 侧 `service <name> ... exited` 或 `cannot start service`，并伴随该服务 domain 的 `avc: denied` 行；genfs 标签缺失表现为访问 `/proc`、`/sys` 节点时的 `avc: denied`，`tclass` 为 file 或 dir；file_contexts 未覆盖则表现为新路径下的文件被统一标成 `vendor_file`。三者的共同上游后果是依赖该 HAL 的 framework 服务阻塞在 `waitForService` 上，system_server 走不完启动序列，而 bootanim 因始终收不到 boot_completed 而持续播放。**以上为预测，本项目尚未执行这些验证**；采集手段见第 5 章。

### 3.7 小结

本章结论：A16 设备树与 A17 系统之间的契约缺口**全部落在 system_server 档**，而 sepolicy 版本号本身不是元凶。候选根因排序如下：

1. **HAL 域缺失 / genfs 与 file_contexts 覆盖不足** —— 最可能导致 HAL 服务起不来 → system_server 等超时
2. **seccomp syscall 缺口** —— 与第 1 项并列
3. **VINTF 声明与实际服务不一致** —— 本身不阻断启动，作用是为"是哪个 HAL"提供证据链
4. **VNDK 废弃导致的 dlopen 失败**
5. ~~nofail 挂载~~ —— **已排除**

第 1 项与第 2 项并列而非有先后，理由在于：两者机制不同（`avc: denied` 只拒绝单次操作 vs `SIGSYS` 直接杀死线程），但**症状形态完全相同**——都只在运行期炸、都不让构建失败、都能让 system_server 崩溃或阻塞而动画照播。因此定因**不能靠先验排序**，必须靠 3.9 的区分方法做一次对照实验。

### 3.8 动态签名与可判读性

- **签名 S1（sepolicy 域/标签/属性缺口）**：`avc: denied { <perm> } for scontext=u:r:<domain>:s0 ... tclass=<cls> permissive=0`，且该行时间上**晚于** `Loading SELinux policy`，并伴随 init 的 `service <name> ... exited`。
- **签名 S2（策略加载失败 —— 与本章现象互斥）**：`SELinux: Could not load policy` 后 init `FATAL` 中止（[init/selinux.cpp](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/selinux.cpp)）。出现 S2 即说明"卡动画"这个现象本身不成立。

**E2 的前置条件（否则会得到假阴性）**：`androidboot.selinux=permissive` 只有在 init 编译期宏 `ALLOW_PERMISSIVE_SELINUX` 打开时才被读取；关闭时 `IsEnforcing()` 无条件返回 `true`，该参数被**静默忽略、init 不中止**（同上）。该宏按构建变体决定（`user` 关闭、`eng`/`userdebug` 打开）；本项目 lunch 目标为 `lineage_pandora-trunk_staging-userdebug`，故应当可用，但**必须实测确认**。

**开关生效的自证**：permissive 下 AVC 仍会被记录，只是不执行拒绝，因此同一批 avc 行的 `permissive=0` 会变成 `permissive=1`。这是最可靠、且无需 shell 的开关生效证据。

| E2 结果 | 判读 |
|---|---|
| avc 行变为 `permissive=1` 且能进系统 | sepolicy 缺口**证实** |
| avc 行变为 `permissive=1` 但仍卡动画 | sepolicy **排除**，转向 VINTF / VNDK / seccomp |
| avc 行仍为 `permissive=0` | 实验无效（宏未开或参数未进 bootconfig），结论记为**待定**，严禁记为排除 |
| 出现 S2 | 与现象矛盾，说明刷入的镜像不是原故障态 |

### 3.9 必须与 SELinux 区分开的两类"安全策略"故障

SELinux 拒绝 → `avc: denied ... permissive=0`，进程继续运行、单个操作失败，或 init 拒绝拉起服务。seccomp 拦截 → 线程收到 `SIGSYS`，tombstone 中出现 `signal 31 (SIGSYS), code 1 (SYS_SECCOMP)` 与 `Cause: seccomp prevented call to disallowed <arch> system call <N>`（[Diagnose native crashes](https://source.android.com/docs/core/tests/debug/native-crash)）。

设备树的 `seccomp_policy/*.policy` 是按 A16 的 syscall 集合写的，A17 的新二进制若调用未放行的 syscall 会被 seccomp **直接杀死**，而不是 avc denied。若被杀的线程位于 system_server 内，进程崩溃 → zygote 重启 → 动画无限播，与现象同样吻合。因此 seccomp 策略缺口应与 sepolicy 缺口**并列**列入候选根因。

### 3.10 keymint/keymaster：两个必须分开的机制

vold 解 FBE 确实依赖 keymint：keystore 最多开 15 个并发操作，"leaving one for vold to use for password encryption"（[KeyMint functions](https://source.android.com/docs/security/features/keystore/implementer-ref)）。但"keymint 导致 `/data` 解不开"实际有**两个互不相同**的机制，检查方法与结论都不同：

**机制 A：密钥与 `Tag::ROOT_OF_TRUST` 的密码学绑定。** KeyMint 的密钥授权数据含 `Tag::ROOT_OF_TRUST`，它绑定的是**创建该密钥时**验证过的启动状态（vbmeta 摘要 + 设备锁状态）。LOS 替换了整条 vbmeta/AVB 信任链，而原厂 A17 创建 `/metadata` 里那份 key blob 时的 ROOT_OF_TRUST 记录的是原厂的信任链——**两者必然不同**。因此 vold 即便能调通 KeyMint、HAL 版本完全匹配，用新信任链验证旧 blob 的授权数据仍会失败，返回 `ErrorCode::VERIFICATION_FAILED`。这与"反复刷写导致的 version binding 棘轮"是两个独立成因：**棘轮失效即使不发生，机制 A 也足以让解密失败**。

**机制 B：version binding 的降级失效。** 官方表述："any reversion of the device to a previous release causes the keys to be unusable"（[Keystore](https://source.android.com/docs/security/features/keystore)）。本项目时间线（原厂 A17 已棘轮密钥 → LOS 未 wipe 直接接管同一份 `/data`）使这一条件结构性成立。

**症状归属必须写死**：keymint 起不来 → `/data` 解不开 → init 停在 `post-fs-data` 或 bootloop，**不会出现"动画照播"**；若刷机前已 wipe `/data`，首启直接 format，根本不走解密路径，缺口被绕过。故在"动画在播"这一前提下，keymint 只能解释 system_server 内 keystore 相关调用失败，不能解释卡在动画。

另需注意：**TWRP 解不开 `/data` 不能单独作为 LOS keymint 缺口的证据**——该 TWRP 树底座是 fox_12.1-a14（Android 14），与 A17 blobs 差三代，它自身就缺新版本 keymint 支持。它是"同方向的更极端对照"，不构成同一命题的证据。

### 3.11 本章结论的三处"排除"

本章有 3 处结论是排除性的（sepolicy 版本号、nofail 挂载、keymint 作为卡动画解释），其价值在于收窄搜索空间而非论证详尽：sepolicy 版本差会被 mapping 机制兼容且以"回退即时编译"处理；nofail 条目失败不计入 `error_count`；keymint 的症状是 bootloop 而非卡动画。三者均已在 3.3 / 3.5 / 3.10 给出源码级依据。

---

## 4. 运行期数据状态：/data 与 /metadata 的跨大版本残留判定

### 4.1 论点：三道串联闸门，且只在"进程未跑完"时阻塞

第 3 章论证"代码契约"缺口。本章论证与之正交的第二个维度：**持久化数据状态**。

开机动画"永远播"不是因为 UI 出错，而是**没有人去关掉它**：`surfaceflinger` 与 bootanim 已运行，但 `zygote` 从未被 `start`，`system_server` 从未就绪，bootanim 等不到停止指令。zygote 之前立着三道闸门，全部写在 init.rc：

1. `/data` 挂载（`on late-fs` 的 `mount_all`，依赖 vold 与 KeyMint）
2. `wait_for_prop apexd.status activated`，其上一行注释写明 "Wait for apexd to finish activating APEXes before starting more processes."
3. `wait_for_prop odsign.verification.done 1`（`on zygote-start` 首条命令，其后才是 `start zygote`）

（[init.rc](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc)）

**本章的核心机制命题**：

> 后两道闸门**不会因为守护进程"报告失败"而阻塞，只会因为它在置位属性之前就死掉而阻塞**。

理由见 4.3、4.4：apexd 的 `OnStart()` 无论激活成败都会走完，随后由调用方置 `activated`；odsign 的 scope_guard 在任何错误路径上都会置 `verification.done=1`。两个守护进程都被设计成"失败也要放行"，因此**属性永久缺失 = 进程非正常终止**。这把嫌疑从"某个功能坏了"精确收窄到"某个进程起不来"，直指 KeyMint/keystore 链路。

### 4.2 证据表：init.rc 原始 mkdir 行与加密属性

判定规则来自 AOSP FBE 文档："`init` applies the **system DE key** to all top-level directories of `/data`, except for directories that must be unencrypted … **Encryption keys apply recursively and cannot be overridden by subdirectories**."（[File-Based Encryption](https://source.android.com/docs/security/features/encryption/file-based)）init 语言定义："`Require`: encrypt directory, abort boot process if encryption fails"；"`None`: take no encryption action; directory will be encrypted if parent is."（[init/README.md](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md)）

| 路径 | init.rc 原始行（逐字） | 标志 | 判读 | TWRP 可读 |
|---|---|---|---|---|
| `/data/misc` | `mkdir /data/misc 01771 system misc encryption=Require` | Require | **System DE** | ✅ |
| `/data/misc/keystore` | `mkdir /data/misc/keystore 0700 keystore keystore` | 无 → 继承 | **System DE** | ✅ |
| `/data/misc/odsign` | `mkdir /data/misc/odsign 0710 root system` | 无 → 继承 | **System DE** | ✅ |
| `/data/misc/bootanim` | `mkdir /data/misc/bootanim 0755 system system` | 无 → 继承 | **System DE** | ✅ |
| `/data/system` | `mkdir /data/system 0775 system system encryption=Require` | Require | **System DE** | ✅ |
| `/data/system/dropbox` | `mkdir /data/system/dropbox 0700 system system` | 无 → 继承 | **System DE** | ✅ |
| `/data/system/environ` | `mkdir /data/system/environ 0700 system system` | 无 → 继承 | **System DE** | ✅ |
| `/data/tombstones` | `mkdir /data/tombstones 0775 system system encryption=Require` | Require | **System DE** | ✅ |
| `/data/dalvik-cache` | `mkdir /data/dalvik-cache 0771 root root encryption=Require` | Require | **System DE** | ✅ |
| `/data/apex` | `mkdir /data/apex 0755 root system encryption=None` | None | **Unencrypted 类**（受 metadata 加密保护，无 FBE 策略） | ✅ |
| `/data/apex/active` / `backup` | `mkdir /data/apex/active 0755 root system` / `mkdir /data/apex/backup 0700 root system` | 无，父为 None | **Unencrypted 类** | ✅ |
| `/data/user/0`、`/data/misc_ce/0`、`/data/system_ce/0` | 容器 `mkdir /data/user 0511 system system encryption=None` 等 | 子目录运行时装 per-user 密钥 | **CE** | ❌ 需解锁 |

**结论**：`/data` 下真正 CE 的只有 per-user 目录。本报告全部取证目标——tombstones、dropbox、odsign、keystore、apex、dalvik-cache——**都是 System DE 或 Unencrypted，只要 `/data` 挂上就能读，不需要 PIN、不需要 Gatekeeper**。

> **方法论提醒**：`encryption=` 这个参数名**极易误读**——它描述的是"加密动作的强制性"（设不上是否中止启动），不是"加密归属"（CE 还是 DE）。本章与第 5 章初稿曾各自在此栽过一次，方向恰好相反。凡引用该参数，务必以 FBE 文档"init applies the system DE key to all top-level directories of `/data`"一句为准。

### 4.3 论据一（第一嫌疑）：`/data` 的跨系统可挂载性

**实测事实：两侧加密参数逐字一致，参数漂移假设排除。** 原厂 OS4.0.5.0 与 LOS 24 的 `vendor/etc/fstab.qcom`，`userdata` 行的三组加密参数逐字相同：

```
fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0
keydirectory=/metadata/vold/metadata_encryption
metadata_encryption=aes-256-xts:wrappedkey_v0
```

唯一差异是 LOS 在 `inlinecrypt` 后多出 `,atgc`——f2fs 的 active GC 挂载选项，属性能调优，不涉及加密格式。**故"A16 设备树声明了与 A17 原厂不同的加密参数 → `/data` 解不开"这条假设排除。** 附带影响：`fileencryption` 定义落盘格式、"it cannot be changed by an OTA"（[FBE](https://source.android.com/docs/security/features/encryption/file-based)）这条通识在本机**不构成风险**，因为两侧声明的就是同一份格式。

**时间线使 version binding 条件结构性成立。** 本项目已确认的时间线：

1. 测试中多次执行 `fastboot -w`
2. 之后完整恢复原厂 A17（7 个物理分区 + super）并**正常启动**——原厂系统重新初始化 `/data`，用**原厂密钥**加密
3. 最后刷 LOS（modfix 版）时**未 wipe**

因此**当前 `/data` 是原厂 A17 加密的，LOS 未格式化直接接管了它**。这不是"可能漂移"，而是一个确定的状态转移。

`/metadata` 存"保护元数据加密密钥的 KeyMint blob"："nothing in the userdata partition can be read until the metadata encryption key is present, the partition table must set aside a separate partition called the metadata partition for storing the KeyMint blobs that protect this key"（[Metadata encryption](https://source.android.com/docs/security/features/encryption/metadata)）。同一页另有死锁警告："KeyMint must be running and ready before init attempts to mount `/data`"，否则 "for the duration of this call, `init` is blocked"。

key blob 受 version binding 约束：

> "when a key with a given version and patch level is used on a device that has been upgraded to a newer version or patch level, the key is upgraded before it can be used, and the previous version of the key invalidated. … **any reversion of the device to a previous release causes the keys to be unusable**."（[Keystore](https://source.android.com/docs/security/features/keystore)，History → Android 7.0 version binding 段）

**原厂 A17 已把密钥棘轮到自身 patch level，LOS 24 未 wipe 直接接管同一份 `/data`，构成一次 reversion。** 密钥只向前棘轮、降级即失效、且不自我修复——这正是本机"两次跨版本接管同一份 data"的必然后果，而非偶发。`security_patch` 比对的作用因此不是"判断是否成立"，而是**量化跨越了多少个 patch level**，并作为 E1b 之后复核密钥是否被重新生成的对账基准。

**结论：`/data` 侧嫌疑已收敛为单一可检查项——`/metadata/vold/metadata_encryption/` 的 blob 是否仍能被当前 KeyMint 解开。** 这个物件在明文分区上可直接 `ls -l`，其存在性与 mtime 即可与刷机时间线对齐，无需任何解密能力。

**为什么 `/data` 挂不上会导向「卡动画」而非 bootloop**：`fs_mgr_mount_all()` 对 `no_fail` 条目失败只打印 "Ignoring failure to mount…" 而不 `++error_count`，**但这条不适用于 `/data`**：`userdata` 的 fs_mgr_flags 是 `latemount,wait,check,...`，**没有 `nofail`**；且 `no_fail` 检查位于 `should_use_metadata_encryption(...)` 的 else 分支——**metadata 加密路径根本不检查 `no_fail`**，其 `error_count` 只由 `call_vdc`（`vdc cryptfs mountFstab`）的成败决定。

**关键在下一步**：`FS_MGR_MNTALL_FAIL` 会让 `mount_all` 返回 Error，但 **init 对返回 Error 的命令是记录后继续**（`Action::ExecuteCommand()` 只记日志、`ExecuteAllCommands()` 继续下一条），**不中止队列**。所以 `/data` 挂载失败后，队列仍能推进到 `on boot`、SurfaceFlinger 启动、动画开播；而 zygote / system_server 因无 `/data` 起不来，`bootFinished()` 永不到达。**这正是「卡动画」而非 bootloop 的机制解释。**

### 4.4 论据二：apexd 闸门——三种互斥情形

`OnStart()` 的失败分支：`ActivateApexPackages` 失败 → `RevertActiveSessionsAndReboot` → `ActivateMissingApexes`。关键结构事实：**`OnStart()` 内部不调用 `OnAllPackagesActivated()`**，该函数由调用方在 `OnStart()` 返回后触发；且失败分支之后 `OnStart()` 仍继续执行 `RemoveInactiveDataApex()`、`SnapshotOrRestoreDeSysData()` 并打印 "OnStart done"（[apexd.cpp](https://android.googlesource.com/platform/system/apex/+/refs/heads/main/apexd/apexd.cpp)）。

| 情形 | 条件 | 结果 | 是否支持本章 |
|---|---|---|---|
| **(a)** | 激活失败 + 存在可回滚的 staged/active session | `RevertActiveSessionsAndReboot()` 走到 `Reboot()` → **重启循环** | 否（反复重启，非卡动画） |
| **(b)** | 激活失败 + **无** session | `RevertActiveSessions` 首步即失败返回（注释："This prevents apexd from boot looping a device in case a native process is crashing and there are no apex updates"）→ 不重启 → 回退预装版 → `OnStart` 走完 → `activated` 置位 → **正常前进** | 否（闸门放行） |
| **(c)** | apexd 在置位 `activated` **之前**崩溃/被杀 | 属性停在 `starting` → init 永久阻塞 → zygote 永不启动 → **动画永播** | **是** |

**只有 (c) 支持本章结论，而 (c) 的成立条件不是"激活失败"，是"apexd 没跑完"。** 落到本项目：`/data/apex/active` 残留旧版 APEX 更可能导向 (b)——能过闸门但后续服务异常，**不产生"动画永播"**。这进一步支持 4.3 的排序。

**最低成本的 apex 残留检验**：`/data/apex` 属 Unencrypted 类，只要 `/data` 挂上即可 `ls -la /data/apex/active`，直接看 .apex 版本号与 mtime。正常设备上该目录应近乎为空（内建 APEX 直接从 `/system/apex` 激活，只有 OTA 更新过才落到 `/data`）（[APEX](https://source.android.com/docs/core/ota/apex)）。

### 4.5 论据三：odsign / derive_classpath——同构机制

`on post-fs-data` 顺序：`derive_sdk` → `init_user0` → `restorecon --recursive --skip-ce /data` → `exec_start derive_classpath` → `load_exports /data/system/environ/classpath` → `start odsign` → `wait_for_prop odsign.key.done 1`；`on zygote-start` 首条即 `wait_for_prop odsign.verification.done 1`。

odsign 先从 keystore 取签名密钥（`KeystoreKey::getInstance(kPublicKeySignature, kKeyAlias, kKeyNspace, kKeyBootLevel)`，alias `ondevice-signing`、nspace 101、boot level 30），失败即 `return -1`。但**正常验证失败并不阻塞**：scope_guard 会 "remove the artifacts and tell Zygote not to use anything"，同时置 `odsign.key.done=1`、`odsign.verification.success=0`、`odsign.verification.done=1`，让 zygote 退化到 JIT（[odsign_main.cpp](https://android.googlesource.com/platform/system/security/+/refs/heads/main/ondevice-signing/odsign_main.cpp)）。

与论据二完全同构：**odsign 只要"跑完"，成败都放行；只有"没跑完"才阻塞。** 阻塞条件 = 进程崩溃、被 SELinux 拒绝、或依赖的 `keystore2`/KeyMint HAL 从未起来。这条把第 3 章的 VINTF 缺口接进本章：KeyMint HAL 未注册 → keystore2 起不来 → odsign 取不到密钥 → 动画永不停。`derive_classpath` 是同一链路第二处风险：`/data/system/environ/classpath` 若残留 A16 的 APEX 路径，后续依赖 CLASSPATH 的进程全部拿到失效路径。

**关于 `wait_for_prop` 的语义**：`do_wait_for_prop()` 本身**只做参数校验 + `start_waiting_for_property()` + `return {}`，立即返回、不阻塞**；真正的阻塞在 init 主循环——`MightBeWaiting()` 为真时跳过 `am.ExecuteOneCommand()`，队列因此停住；属性满足后由属性线程经 eventfd 唤醒（详见 1.6 的机制说明与 [init.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/init.cpp)）。**这一点必须写准**：若写成"`wait_for_prop` 是同步阻塞的 builtin"，审稿打开 `builtins.cpp` 看到它立即返回，就能"反证"论证失败。README 表述 "If property name is already set to value, **continue immediately**" 也印证：立即继续只适用于属性已就位的分支。

### 4.6 论据四：`/metadata`——唯一无需解密即可取证的分区

`/metadata` 下所有 mkdir 均在 `on post-fs` 段且**不带任何 `encryption=` 标志**：`mkdir /metadata/vold`、`mkdir /metadata/apex 0700 root system`、`mkdir /metadata/apex/sessions 0700 root system`、`mkdir /metadata/staged-install 0770 root system`。fstab 条目亦无 `fileencryption=`，AOSP 标准行为 `… /metadata ext4 noatime,nosuid,nodev,discard wait,check,formattable`（[Metadata encryption](https://source.android.com/docs/security/features/encryption/metadata)）。原因直白：它必须在 `/data` 可解密**之前**被读取，故不能自身依赖 FBE。

**这是全报告唯一 100% 可靠、不依赖 KeyMint 的残留证据源。** 即使 TWRP 完全解不开 `/data`，`/metadata/apex/sessions`、`/metadata/vold/metadata_encryption`、`/metadata/watchdog` 依然可读。

### 4.7 判据汇总

| 数据状态异常 | 阻塞闸门 | TWRP 下可观测判据 | 加密属性 | 特征 |
|---|---|---|---|---|
| **fstab 加密参数与落盘格式不符** | — | **已排除**：两侧 `userdata` 行加密参数实测逐字一致 | — | **排除项**，保留以示排除过程 |
| `/data` 解不开 | `/data` 挂载 | TWRP 直接尝试挂载；失败即记录 | — | **高度支持**首要假设，但**不能单独定案**——TWRP 是 fox_12.1-a14 底座，KeyMint 通路与 LOS 24 不同 |
| key blob 失效 | `/data` 挂载 | `/metadata/vold/metadata_encryption/` 下 blob 是否存在及 mtime | 明文分区 ✅ | blob 在但解不开；mtime 与"最后刷 LOS 未 wipe"的时间点对齐 |
| vold 无 CE/DE 密钥 | `/data` 挂载 | `/data/misc/vold/user_keys/{ce,de}/0/` 是否为空 | System DE ✅ | 空 = 该 data 从未被 LOS 成功解锁过 |
| 挂载失败细节 | `/data` 挂载 | `recovery.log` / dmesg 中 `fs_mgr`、`vold` 报错行 | — | 取代不可观测的"对比可解性" |
| apexd 未跑完 | `apexd.status` | `ls -ld /data/misc/bootanim` 是否**存在** | System DE ✅ | **缺失=强判据**；**存在=无信息量**（mkdir 幂等，原厂 A17 启动过就必然创建过） |
| `/data/apex/active` 残留旧版 | （通常不阻塞，情形 b） | `ls -la /data/apex/active` 的版本与 mtime | Unencrypted ✅ | 有早于本次刷机的包；正常应近乎为空 |
| 未提交 staged session | `apexd.status`（情形 a 会重启） | `/metadata/apex/sessions/` 是否非空 | 明文分区 ✅ | **待实测确认**（按目录命名与 init.rc 创建位置推断） |
| 备份残留 | 同上 | `/data/apex/backup/` | Unencrypted ✅ | 有 .apex；成功后应被 `DeleteBackup()` 清空 |
| odsign 未跑完 | `odsign.verification.done` | `/data/misc/odsign/` 目录内容与 mtime | System DE ✅ | 文件名见下 |
| CLASSPATH 残留旧路径 | odsign 依赖链 | `/data/system/environ/classpath` 的**内容** | System DE ✅ | 引用 `@A16` 版本路径 |
| ART 工件失配 | zygote 反复 crash | `/data/dalvik-cache`、`/data/misc/apexdata/com.android.art/dalvik-cache` | System DE ✅ | 删除即良性对照实验 |
| **启动时间轴 A（首选）** | — | `ls /data/system/dropbox \| sort`，文件名内嵌毫秒时间戳 `<tag>@<ts>.<ext>` | System DE ✅ | 最可靠、最便宜的"本次启动走到哪一步"时间线 |
| **启动时间轴 B（备选）** | — | `/data/system/environ/classpath` 的 **mtime**（由 `load_exports` 写入，位置在 bootanim 之后） | System DE ✅ | **待实测确认**——未核实该文件是否每轮必写 |

**关于 `/data/misc/bootanim`：为什么不能用 ctime / mtime。** 曾考虑用 `ls -lc` 的 ctime 作水位线（理由：init README 称 `mkdir` 会更新已存在目录的 mode/owner，而 `chmod`/`chown` 刷新 ctime）。**该方案不成立**——README 是概括性描述，实现是条件幂等逻辑。`init/builtins.cpp` 的 `make_dir_with_options()`：

```cpp
bool needs_chmod = (mstat.st_mode & ~S_IFMT) != options.mode;
if ((options.uid != (uid_t)-1 && options.uid != mstat.st_uid) ||
    (options.gid != (gid_t)-1 && options.gid != mstat.st_gid)) {
    if (lchown(options.target.c_str(), options.uid, options.gid) == -1) { ... }
    needs_chmod = true;
}
if (needs_chmod) {
    if (fchmodat(AT_FDCWD, options.target.c_str(), options.mode, AT_SYMLINK_NOFOLLOW) == -1) { ... }
}
```

`lchown` 只在 uid/gid 与现值不同时调用；`fchmodat` 只在 mode 与现值不同时调用。`/data/misc/bootanim` 正常状态就是 `0755 system system`，两个条件都不满足，**两个系统调用都不执行，ctime 不更新**。mtime 同样不行（`mkdir` 对已存在目录不触碰 mtime）。故这条路整条不通，只剩"缺失"一支可用。

**但要保留该判据的语义强度**：该行位于 `restart apexd` → `wait_for_prop apexd.status activated` → `perform_apex_config` **之后**，因此「**缺失 ⇒ apexd 从未激活成功**」依然是强判据——只是它只在"目录不存在"这一侧有效。当前 `/data` 未经 wipe、原厂 A17 启动过，该目录必然存在，故在当前状态下这条判据**不产生信息**，仅在后续 wipe 对照实验后恢复效力。

**关于 `/data/misc/odsign` 文件名回源**：取自 `odsign_main.cpp` 的字符串常量——`publickey.signature`、`key.cert`、`odsign.info`、`odsign.info.signature`（[odsign_main.cpp](https://android.googlesource.com/platform/system/security/+/refs/heads/main/ondevice-signing/odsign_main.cpp)）。若无法回源，建议退化为"该目录内文件的 mtime 是否停留在上一个系统"，不点名具体文件。

### 4.8 本章不能排除什么

| 假设 | 归属 | 判定方式 | 若为真 |
|---|---|---|---|
| key blob version binding 失效 / `/data` 解不开 | **本章（第一嫌疑）** | TWRP 能否挂载 `/data`；blob mtime；`security_patch` 对账 | `/data` 永不挂载，闸门卡死 |
| apexd / odsign 进程未跑完 | **本章（第二层）** | `/data/misc/bootanim` 缺失、`/data/misc/odsign` mtime | 属性永不置位，zygote 永不启动 |
| VINTF / sepolicy / VNDK 契约缺口 | 第 3 章 | VINTF manifest 比对、avc denied | HAL 起不来 → 连锁失败 |
| GKI module_layout / vendor_boot 不匹配 | 第 2 章 | module_layout CRC 静态复核 | 模块加载失败，通常更早崩 |

**本章的自证伪条件**：若实测确认 `/data` 可正常挂载、`/metadata` 中 key blob 完好且能被当前 KeyMint 解开，则本章两个假设同时被证伪，嫌疑应整体回到第 3 章或第 2 章。这一条是"假设互斥可判定"的落点。

### 4.9 小结

本章把"动画永不停"还原为三个可命名的阻塞点：`/data` 挂载、`apexd.status`、`odsign.verification.done`。三者都在 zygote 之前、都由持久化状态驱动、都不留崩溃栈——这解释了 pstore 为空：问题不在内核，而在一个永远等不到的属性。

**经实测与时间线修正后的排序**：`/data` 侧嫌疑已收敛为单一可检查项——`/metadata/vold/metadata_encryption/` 的 blob 是否仍能被当前 KeyMint 解开。当前 `/data` 由原厂 A17 加密、LOS 未 wipe 直接接管，使 version binding 的触发条件结构性成立，这一嫌疑的优先级高于任何 apex/odsign 残留。取证上，`/metadata` 是唯一无条件可读的证据源；`/data` 侧目标全为 System DE 或 Unencrypted，**无需 PIN 与 Gatekeeper**。

---

## 5. 取证与实验设计：无 adb 条件下的证据提取与最小化验证

### 5.1 前提校正：先确认「无 adb」到底是什么

本章的全部设计建立在「拿不到运行期日志」这一前提上。但该前提本身必须先被验证，因为它有三种完全不同的成因：

| `adb devices` 输出 | 含义 | 对本章的影响 |
|---|---|---|
| `unauthorized` | **adbd 已启动**，仅未获主机密钥授权 | 「无 adb」不成立，本章应改写为「有 adb 但需先解决授权」 |
| 空列表 | adbd 未启动，或 USB 未配置到 adb 模式 | 维持本章前提 |
| `offline` | adbd 启动了但未就绪 | 介于两者之间 |

**为什么这条必须最先做**：`adbd` 与 `surfaceflinger` 同属 `class core`，由 `on boot` 段的 `class_start core` 一并拉起（[surfaceflinger.rc](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/surfaceflinger.rc)、[rootdir/init.rc](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc)）。**既然开机动画在播，就说明 `class_start core` 已执行，adbd 极大概率也已被拉起。** 此时「adb 连不上」更可能的原因是：

- **userdebug 构建的 adb 授权对话框由 system_server 弹出**，而 system_server 未就绪，对话框永不出现 → 主机永远停在 `unauthorized`；
- 或 `persist.sys.usb.config` 沿用了原厂值（本项目最后刷 LOS 未 wipe，该 persist 属性很可能仍是原厂的 `mtp`），USB 未被切到 adb 模式。

**这条 10 秒验证的结论分叉极大**，但分叉点不是「有没有 adb」，而是「能不能拿到 shell」：

- **显示 `device`** → `adb_keys` 中已有本机公钥，无需授权对话框；取证设计整体改写为「有 adb」路径，"零日志"约束作废，可直接取 logcat。
- **显示 `unauthorized`** → adbd **活着**但无法取得 shell（授权对话框依赖 system_server），本章前提**不变**，只是多了一条"adbd 已起、`class_start core` 已执行"的旁证。
- **空列表 / `offline`** → adbd 未起或 USB 未切到 adb 模式，维持本章前提。

**在任何 pstore / tombstone / dropbox 取证之前，先跑 `adb devices`。**

**一条可能直接解锁取证的持久化事实**：adb 授权公钥持久化在 `/data/misc/adb/adb_keys`，而本项目**刷入 LOS 时没有 wipe `/data`**。若这台机器在原厂 A17 时曾授权过同一台 PC，adbd 启动后会直接认它——**即使 system_server 从未起来、授权对话框从未出现，`adb devices` 也可能显示 `device`**。

这有两个后果：

- **判据可用性**：若显示 `device`，logcat 可取，第 5 章的全部取证路径直接可用，本报告"零日志"的前提部分失效；
- **`unauthorized` 的解释要收窄**：它**不能**单独推出"system_server 未起"——也可能只是"这台 PC 从未在此设备授权过"。只有在**已知该 PC 曾授权过**时，`unauthorized` 才是强判据，否则是中性的。

可操作验证：TWRP 下 `ls -l /data/misc/adb/adb_keys`，看是否存在、内容里有无对应公钥。`/data/misc` 属 System DE，挂上即可读。

### 5.2 为什么 pstore 为空：机制必然，但证据力有边界

ramoops 是"an oops/panic logger that writes its logs to RAM before the system crashes"，只在 `kmsg_dump`（oops/panic/watchdog 类）触发时落盘。**用户态 hang 不触发 `kmsg_dump`**，故"卡动画 + pstore 为空"是自洽的、预期的组合，不能据此怀疑 ramoops 链路没配好。

本项目的 ramoops 链路确实完整：内核二进制含完整 ramoops / pstore / persistent_ram 符号，12 个 dtb 全部有 `ramoops-region` 节点（0xff400000，2 MB，`console-size` 与 `pmsg-size` 各 1 MB），TWRP 的 `init.rc` 有 `mount pstore pstore /sys/fs/pstore`。

但"pstore 为空"作为证据有**四条边界**，缺一条就会误判：

1. **记录跨重启保留，不是每次启动清空**。内核文档原文："The module uses a counter to record multiple dumps but the counter gets reset on restart (i.e. new dumps after the restart will overwrite old ones)."（[ramoops](https://docs.kernel.org/admin-guide/ramoops.html)）——缓冲区**不会**在启动时清空，是"新 dump 覆盖旧记录"。因此 pstore 为空 = 从未发生过 `kmsg_dump`，或旧记录校验失败被丢弃。
2. **冷复位后 DDR 内容不保证保留**。ramoops 支持**软件 ECC**，"This might be useful when a hardware reset was used to bring the machine back to life (i.e. a watchdog triggered). In such cases, RAM may be somewhat corrupt, but usually it is restorable."（同上）本项目 ramoops 节点**没有 `ecc` 属性**，故长按电源的冷复位之后，即使曾写过 dump 也捞不回来。**该判据只在 warm reset（`fastboot reboot`、panic 自复位、看门狗硬复位）之后成立**——这是一条零成本、却能救活整条证据链的流程纪律：**复现一律以 `fastboot reboot` 收尾，禁止长按电源**。
3. **读到的必须是本次故障的那份**。若期间又刷过机（boot 分区被替换），读到的可能是更早一次的内核日志。
4. **TWRP 跑的是 recovery 分区的内核**（recovery.img `kernel_size=0`，内核取自 boot），能否读到 pstore 取决于该内核是否启用 `CONFIG_PSTORE_RAM`、且 ramoops DT 节点地址与之一致。不满足时，"pstore 为空"只说明"根本没挂上 ramoops"，与"有没有 panic"无关——**这是最容易被误读成反证的情形**。

### 5.3 取证顺序纪律：不可逆操作必须排在最后

本章列出的取证动作并非等权，其中至少一项不可逆：`logcat -L -c` 会直接 `unlink("/sys/fs/pstore/pmsg-ramoops-0")`，把上一轮唯一的一手日志永久删除（[logcat.cpp](https://android.googlesource.com/platform/system/logging/+/refs/heads/main/logcat/logcat.cpp)）。顺序必须写死：

**① 进 TWRP 第一件事读 pstore**（`ls -l /sys/fs/pstore/` 并 `cp` 出 `console-ramoops*`、`pmsg-ramoops-0`、`dmesg-ramoops-*`）→ **② 再导出 `logcat -b all -L`（只读）** → **③ 最后才做任何带清理语义的操作**（format data、wipe、`-L -c`）。

判据：**任何会清掉 `/sys/fs/pstore/` 内容的命令，都必须在三处快照与 pmsg 导出完成之后才允许执行。**

### 5.4 TWRP 下最值得捞的三处

前提澄清：「无 adb」仅指 LOS 内 adbd 未起；**TWRP 自带 adbd**，取证通道存在，操作通过 `adb shell` 在 TWRP 内完成。

**（0）`/metadata` —— 优先级最高，因为它是明文**

`/metadata` 的 fstab 行是 `ext4 noatime,nosuid,nodev,discard wait,check,formattable`，无任何加密标志；init.rc 里 `/metadata/*` 全部在 `on post-fs` 段创建，早于 `on post-fs-data`。它存在的理由正是"nothing in the userdata partition can be read until the metadata encryption key is present"——故必须在 `/data` 之前可读（[Metadata encryption](https://source.android.com/docs/security/features/encryption/metadata)）。

**即使 KeyMint 完全坏掉、`/data` 一个字节都读不到，`/metadata` 仍能提供硬结论**：

| 路径 | 看什么 | 什么特征说明什么 |
|---|---|---|
| `/metadata/vold/metadata_encryption` | blob 是否存在、mtime | 存在 → `/data` 曾成功初始化元数据加密；mtime 若为原厂 A17 那次启动 → 说明之后从未 format 过 `/data` |
| `/metadata/apex/sessions` | 是否为空 | 非空 → 存在未提交的 APEX session（此判据为推断，待实测确认） |
| `/metadata/ota/snapshots`、`/metadata/staged-install` | 是否有残留 | 未完成的 OTA/staged 安装会留下状态 |

**（1）`/data/tombstones/` —— native 崩溃栈**

debuggerd 写入 `/data/tombstones/`，`tombstone_00`…`tombstone_NN`，写满覆盖最旧。每份含全部线程 backtrace、浮点寄存器、原始栈转储与完整内存映射（[Debugging Native Android Platform Code](https://source.android.com/docs/core/tests/debug/native-crash)）。

- **看什么**：`*** *** ***` 起始行后的 `pid/tid/name`、`signal`、`Abort message`，以及 maps 里带 `--->` 前缀的故障地址行。
- **什么特征说明什么**：时间戳落在卡动画窗口内、且 `name` 是 `zygote64` / `surfaceflinger` / `vold` / `apexd` 之一 → framework/blobs 契约缺口导致 native 初始化崩溃；`signal` 为 `SIGSYS` + `SYS_SECCOMP` → 指向 seccomp 过滤；空目录 → native 层干净，故障在 Java 层或纯阻塞。
- **符号化**：`development/scripts/stack < tombstone_06`。
- **注意**：编号会回绕，不宜断言"最新编号最大"，应按 mtime 排序，编号仅作辅助。

**（2）`/data/system/dropbox/` —— system_server 崩溃与 Watchdog 记录**

DropBoxManagerService 默认目录即 `/data/system/dropbox`，文件名为 `urlencode(tag)@<timestampMillis>.<txt|dat>[.gz]`；条目因配额被丢弃时会留下零长度 `.lost` 墓碑（[DropBoxManagerService.java](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/DropBoxManagerService.java)）。

- **最高价值的是 `watchdog@*` 与 `pre_watchdog@*`**：Watchdog 默认超时 60 秒，超时后 dump 全部线程栈、`doSysRq('w'/'m'/'l')`、写 dropbox，然后 `Process.killProcess(myPid)` + `System.exit(10)`（[Watchdog.java](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/services/core/java/com/android/server/Watchdog.java)）。system_server 被杀后由 init 重启，**重启期间开机动画不会退出**——与"永久卡动画"形态完全吻合。
- 其次看 `system_server_crash@*`、`SYSTEM_TOMBSTONE@*`、`system_app_anr@*`。若只见到 `.lost` 文件，tag 与时间戳仍有效——**"内容丢了"不等于"事件没发生"**。
- **时效警告**：dropbox 默认保留 3 天、最多 1000 个文件、配额 userdebug 20 MB。**取证必须在最后一次复现后 3 天内完成**，否则证据自动蒸发。
- **额外价值**：文件名内嵌毫秒时间戳，`ls | sort` 直接给出**按毫秒排序的事件时间线**，这是本项目最便宜的"启动走到哪一步"时间轴。

**（3）`/data/misc/bootanim/` —— 只能单向使用**

AOSP `BootAnimation.cpp` 定义 `BOOTANIM_DATA_DIR_PATH[] = "/data/misc/bootanim"`、`BOOTANIM_TIME_DIR_PATH[] = "/data/misc/bootanim/time"`，以及 `time/last_time_change`、`time/time_is_accurate`、`time/time_format_12_hour` 三个标志文件，由 `BootAnimation::TimeCheckThread` 用 inotify 监视以判断 RTC 是否已同步。

因此它的正面价值是：**这些文件存在 ⇒ bootanimation 进程已启动并跑进 `TimeCheckThread`**——即"卡动画 = userspace 已起"的一条动态正向证据。

但它**不能**用作 init 执行深度的水位线：

- **存在是弱信号**：`/data` 持久、`mkdir` 幂等，原厂 A17 启动过就必然创建过该目录；本项目最后刷 LOS 未 wipe，故其存在对本次启动零信息量。
- **ctime / mtime 也不可用**：`init/builtins.cpp` 的 `make_dir_with_options()` 中，`lchown` 只在 uid/gid 与现值不同时调用、`fchmodat` 只在 mode 与现值不同时调用；`0755 system system` 恰好匹配，两个调用都不执行，**时间戳不刷新**。
- **只有"缺失"是强判据**：目录不存在 ⇒ 这份 `/data` 上从未有任何启动走完 `on post-fs-data` 到该行（该行位于 `restart apexd` 与 `apexd.status activated` 之后）。

### 5.5 pmsg 残留：最可能捞到"卡住那一刻"的一手日志

本项目 ramoops 节点带 `pmsg-size 1MB`，这是全章最有性价比的一手材料。官方读法是 `logcat -b all -L`，其帮助文本为"Dump logs from prior to last reboot from pstore"，实现为 `ANDROID_LOG_PSTORE | ANDROID_LOG_NONBLOCK`，读的就是 `/sys/fs/pstore/pmsg-ramoops-0`；而 `-c` 与该节点组合时会直接 `unlink` 它（[logcat.cpp](https://android.googlesource.com/platform/system/logging/+/refs/heads/main/logcat/logcat.cpp)）。

三点实操结论：

1. **缓冲只有 1 MB 且环形覆盖**——恰好是"卡死瞬间"的最后 1 MB，信息密度极高。
2. **pmsg 的有无本身又是一条水位线**：logd 只有跑起来才会往 pmsg 写。pmsg 有内容 → logd 已启动，故障在 logd 之后；pmsg 全空 → 故障早于 logd。
3. **禁用 `logcat -L -c`**：它会 unlink 掉 pmsg 节点，是不可逆的取证破坏。

TWRP 内的可用性需实测确认，建议自检：`which logcat; ls -l /dev/pmsg*; ls -l /sys/fs/pstore/`。失败时退化为直接 `cat /sys/fs/pstore/*`。

### 5.6 其他取证路径的可行性排序

| 序 | 通道 | 门槛 | 能回答什么 |
|---|---|---|---|
| 1 | **`adb devices` 判别** | 10 秒 | adbd 是否活着；本章前提是否成立 |
| 2 | **TWRP + adb shell** | 已具备 | `/metadata` 快照 + 三处取证 + pmsg |
| 3 | **`fastboot getvar`** | 零成本 | `current-slot`、`slot-retry-count`、`slot-unbootable`、`slot-successful`（[Implement A/B updates](https://source.android.com/docs/core/ota/ab/ab_implement)） |
| 4 | **UART 串口** | 需拆机 | 卡 logo 阶段首选，覆盖 kernel 起来之前的故障 |
| 5 | **EDL memorydump** | 门槛最高 | 需 0x9008 模式 + 匹配 firehose loader；SM8850 新平台 loader 稀缺 |

**第 3 项是本项目被低估的强证据**：`slot-retry-count` 递减或 `slot-unbootable:yes` 说明 bootloader 判定启动失败；保持满值且未标 unbootable 说明 bootloader 已"放手"、控制权交给内核。**反向自证**（需前提"症状可稳定复现"）：若 retry-count 真被耗尽，设备会在若干次失败后改判、症状随之变化，而不会每次都稳定停在同一个动画。

### 5.7 控制变量实验矩阵

**设计原则**：一次只改一个变量；每个实验先声明"能排除什么"，再声明"失败如何恢复"；每个实验前后各做一次完整快照，并以 `fastboot reboot`（warm）收尾。

**E-1（可达性判定，先于一切实验）**

| 观测 | 判读 | 后续可用实验 |
|---|---|---|
| `adb devices` 报 `unauthorized` | adbd 活着，本章前提改写 | 全部实验可用，且可尝试 `ro.adb.secure` 排查 |
| `mount /data` 成功、`ls /data` 见明文 | 三处取证全可用（System DE，无需解锁） | E1a 与 E1b 均可用 |
| `mount /data` 失败、`mount /metadata` 成功 | `/data` 侧取证失效，但 `/metadata` 侧可用 | **跳过 E1a，直上 E1b** |
| 两者皆失败 | 动态取证线整体失效 | 只剩 getvar + 静态比对 |

**E0（先验排除，不需要实验）**：fstab 与原厂的差异只落在 `nofail` 条目上，而 `fs_mgr_mount_all()` 对非 metadata 加密的 `no_fail` 条目失败不计入 `error_count`。故「first-stage fstab 失败」整族假设当场排除。反向注意：若某实验只影响 mi_ext/overlay，预期不会出现启动二值差异，**不要把"启动行为没变化"误判为"变量没生效"**。

| # | 实验 | 具体改动 | 能排除的假设 | 恢复路径 |
|---|---|---|---|---|
| **E1a** | 格式化 data | TWRP 内 format data | `/data` 侧残留（**若通过，与 version binding 预测一致，属预期内**） | 原厂完整恢复脚本（约 270 秒） |
| **E1b** | format data + erase metadata | `fastboot erase metadata` + `-w`，绕开 TWRP 的解密依赖 | `/metadata` 侧残留；**兼作 KeyMint 功能验证**（会强制重建 key blob） | 同上 |
| **E2** | permissive 对照 | bootconfig 加 `androidboot.selinux=permissive` | sepolicy 域/标签/属性缺口 | 重刷 vendor_boot |
| **E2b** | seccomp 对照 | diff `seccomp_policy/*.policy`；放宽 system_server/zygote 策略 | seccomp syscall 缺口 | 重刷 vendor_boot |
| **E3** | 只刷逻辑分区、保留原厂物理分区 | 先用原厂 boot 起 fastbootd，只刷 system/product/vendor/system_ext | 物理分区与 A17 blobs 不匹配 | 重刷原厂 super |
| **E4** | 换 recovery 探针 | 把 LOS 内核装到 recovery 槽位 | LOS 内核 + LOS ramdisk 在 recovery 槽位的引导匹配性 | 重刷 boot/recovery |
| **E7** | 关掉开机动画 | 将 bootanim 置为 disabled | 区分"bootanim 自身卡死"与"系统级 hang" | 重刷 |

**E1a/E1b 两臂的判读**（这是矩阵里唯一需要两臂对照的地方）：

| 结果 | 结论 |
|---|---|
| E1a 过、E1b 也过 | `/data` 侧残留成立 |
| E1a 卡、E1b 过 | **`/metadata` 侧残留成立**（单跑 E1a 会误判） |
| 两臂都卡 | 残留假设整体排除，转第 3 章代码契约 |

**E1b 的顺序约束**：`fastboot erase metadata` 会重建 key blob，而**旧 blob 依赖 TEE 内部状态、不可备份**。因此 E1b 之前必须把所有依赖"症状稳定"的判读结论先落盘定稿——**这约束的是结论顺序，不只是取证顺序**。

**E2 的四分支判读**（`permissive=0 → 1` 的自证不能省）：

| 观测 | 判读 |
|---|---|
| avc 行 `permissive=0` → `permissive=1`，且能进系统 | sepolicy 缺口**证实** |
| 转 `permissive=1` 但仍卡动画 | sepolicy **排除**，转 VINTF/VNDK/seccomp |
| **仍为 `permissive=0`** | 实验无效，结论**待定**（严禁记为排除） |
| 出现 `SELinux: Could not load policy` | 策略加载即 FATAL，与"动画照播"互斥 → 刷入的不是原故障态 |

### 5.8 不可靠水位线的四类失效（方法论留档）

本轮研究在三章里各栽过一次同类错误，值得留档：

1. **条件执行型失效**：判据依赖"某个副作用每次都会发生"，但实现是条件执行。例：用 `/data/misc/bootanim` 的 ctime 当逐次启动水位线，而 `make_dir_with_options()` 在属性已匹配时不发 `lchown`/`fchmodat`。
2. **跨重启残留型失效**：判据依赖"某物存在即说明本次做到了"，但该物持久留存。例：用 bootanim 目录的**存在性**当 `post-fs-data` 水位线，而原厂启动过就必然创建过它。
3. **单向性失效**：判据只能证伪不能证实。例：`FscryptSetDirectoryPolicy` 失败会 `reboot_into_recovery`，故"没重启"说明没在这里炸，但**不能**反推走到了这一行。

4. **设计许可当实际配置**：用"AOSP 允许 X"去推"本机构建就是 X"。例：`init/README.md` 说 `animation` 类服务"can be launched very early during bootup"，据此推出"SurfaceFlinger 在 `late-fs` 就起来了"；但本机构建的 `init.rc` 里**没有 `class_start animation`**，SF 实际由 `on boot` 的 `class_start core` 拉起。**设计许可是可能性，实际配置是事实**，排除性论证必须落到后者。

这四类失效的共同点：**把"可能性"或"副作用"当成"已经发生的事实"**。凡水位线判据或排除性论证，先问两句：这个副作用是否每次都无条件发生？这个"允许"在本机构建里是否真的被采用？

### 5.9 证据层级：哪些结论会随实现演进而失效

本报告大量结论依赖源码阅读，读者需要能判断"哪些明年还成立、哪些下个内核版本就得重核"。因此把证据分为两层：

| 层级 | 定义 | 典型例子 | 衰减特性 |
|---|---|---|---|
| **契约层** | 规范、类定义、文档字段语义、构建规则 | `animation` 类"应在 `/data` 不可用时也能工作"；`bootconfig` trailer 布局；`Require` = system DE 密钥 | **不随实现演进失效**，只要规范不改就成立 |
| **实现层** | 具体函数的行为、调用顺序、错误码 | `early_mod_check()` 的检查顺序；`same_magic()` 跳过版本前缀；`queue_fs_event` 只在 `NEEDS_RECOVERY` 上重启 | **随实现变化失效**，内核或 AOSP 改写即需重核 |

**使用规范**：优先用契约层证据支撑排除结论；用实现层证据时，须标注"随实现变化失效"。

按此标准，本报告中依赖实现层的结论有：第 2 章的**闸门顺序**（`check_modstruct_version()` 先于 `check_modinfo()`）与**vermagic 前缀跳过**（`same_magic()` 的行为）两条、第 4 章的 `mount_all` 非阻塞与 `apexd`/`odsign` 的 scope_guard 行为、第 5 章的 `make_dir_with_options()` 条件执行。**这些在第 2 章的口径是"若内核改写相关函数，结论需重核"；其余各章同理。**需要区分的是：第 2 章「`module_layout` 的 CRC 是闸门」这一条**不属于**实现层——它由 `CONFIG_MODVERSIONS` 机制保证，属契约层，函数实现改写不会使其失效。

依据契约层的结论则稳定得多：`animation` 类规范、`bootconfig` 的 trailer 布局与校验规则、`encryption=` 的语义、`/metadata` 的 fstab 明文属性、`/metadata` 与 `/data` 的加密归属划分。

### 5.10 小结

无 adb 不等于无证据，但**"无 adb"本身要先被验证**——`adbd` 与 SF 同属 `class core`，动画在播即意味着它很可能也起来了。pstore 为空是机制必然（用户态 hang 不触发 `kmsg_dump`），且该判据只在 warm reset 后成立；`/metadata` 是唯一不依赖 KeyMint 的取证面；`/data` 侧目标全为 System DE 或 Unencrypted，只要元数据加密解得开即可读。

实验设计上，E-1（可达性判定）必须先于一切，E0（nofail 先验排除）省掉一次刷机，E1a/E1b 两臂区分 `/data` 侧与 `/metadata` 侧残留。

---

## 结论

本报告面对的是一个"零日志"现场：设备能显示开机动画，却永远进不了系统，adb 不通，无串口。在这样的约束下，静态分析能做的不是提出猜测，而是**逐层宣布排除，并把剩余候选压到单条**。

五章完成了一次五级收敛：

1. **bootanim 机制**把"卡动画"形式化为"`bootFinished()` 从未被调用"，从而把内核、first-stage init、SELinux 策略加载、apexd、SurfaceFlinger + display HAL 全部降级为已通过项，故障域锁定在 userspace 服务层。
2. **镜像与模块层**逐字节复核，确认内核与原厂完全相同、ramdisk 清单一致；并借 `early_mod_check()` 的判定顺序证明 CRC 先于 vermagic，`same_magic()` 在带 CRC 时跳过版本前缀。本层结论是"可排除"，并附一条防污染判据——它拦下的是一类会制造假阴性的真实缺陷，而不是当前症状的成因。
3. **构建期契约**把缺口按强制时机分三档，证明 sepolicy 版本差与 `nofail` 挂载都不可能造成启动失败，候选收敛为 HAL 域缺失 / seccomp syscall 缺口（并列）→ VINTF → VNDK。
4. **运行期数据状态**判定 `/data` 下取证目标全为 System DE，唯一障碍是元数据加密；并借本项目自身的时间线（原厂 A17 加密 `/data` → LOS 未 wipe 直接接管）证明 key blob 的 version binding 条件结构性成立。
5. **取证与实验设计**给出可达性判定、顺序纪律与两臂对照矩阵，并把本轮踩到的**四类**"不可靠水位线"留档。

**必须诚实说明的是：本报告没有定案。** 五章收敛到一个很小的候选集，但没有一条被动态证据确认。

初稿阶段第 4 章与第 5 章之间存在一处分歧——"动画在播能否证明 `/data` 已挂载"。该分歧已由 init 的 builtin 语义解开（详见「待完善事项」第 1 条），结论是分层的：**`/data` 挂载失败不被排除**（`mount_all` 失败后 init 记录并继续，队列仍能推进到 `on boot`），而 **apexd / odsign 两道属性闸门被排除**（`wait_for_prop` 同步阻塞，卡住则 `on boot` 不到达、无动画）。

**一条不依赖任何时序假设的机制解释**：`class_start main` 与 `class_start late_start` 位于 `on nonencrypted` 段，而 `nonencrypted` 由 vold 完成解密后**单独触发**，**不在 `late-init` 的 11 个 trigger 序列内**（[init.rc](https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc)）。因此：**`/data` 解密失败 → `nonencrypted` 永不触发 → `class_start main` 不执行 → system_server 永不启动 → `bootFinished()` 永不到来 → 动画永远播。**

这条链条把"动画在播"与"`/data` 解密失败"直接连起来，且不需要回答"init 是否阻塞在 `mount_all`"或"SurfaceFlinger 何时启动"这两个静态无法消解的问题。它同时解释了为什么 keystore / KeyMint 那一层在任何时序论证下都未被覆盖——FBE 凭据解密走的是 `on nonencrypted` 这条独立链。

仍需动态证据确认的是这处分层所依赖的两个前提：① apexd 在无 `/data` 时能否仅凭 `/system/apex` 完成激活；② odsign 的 scope_guard 是否覆盖"取密钥失败"这条路径。两者的判据分别是一次 TWRP 快照中的 `/data/misc/bootanim` 是否存在、`/data/misc/odsign/` 内容是否完整。

**建议的下一步，按信息量排序**：

1. **`adb devices`（10 秒）**——若报 `unauthorized`，则"零日志"前提崩塌，全部取证路径改写，这是投入产出比最高的一步
2. **`/metadata` 快照**——明文可读，即使 `/data` 完全解不开也能给出"是否 format 过""apex 是否中途失败"两条硬结论
3. **E1b（format data + erase metadata）**——同时验证 `/data` 可挂载性与 KeyMint 功能，且能一次性判定 `/metadata` 侧残留
4. **闭合 4/5 章分歧**——确认 `wait_for_prop` 的队列阻塞语义，据此决定 `/data` 假设是保留还是排除

---

## 参考文献

- AOSP. *Boot flow (Verified Boot)*. https://source.android.com/docs/security/features/verifiedboot/boot-flow
- AOSP. *Use Verified Boot*. https://source.android.com/docs/security/features/verifiedboot/verified-boot
- AOSP. *Boot image header*. https://source.android.com/docs/core/architecture/bootloader/boot-image-header
- AOSP. *Vendor boot partitions*. https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions
- AOSP. *Generic boot partition (init_boot)*. https://source.android.com/docs/core/architecture/partitions/generic-boot
- AOSP. *Implement bootconfig*. https://source.android.com/docs/core/architecture/bootloader/implementing-bootconfig
- AOSP. *Kernel module support*. https://source.android.com/docs/core/architecture/kernel/kernel-module-support
- AOSP. *GKI versioning scheme*. https://source.android.com/docs/core/architecture/kernel/gki-versioning
- AOSP. *APEX file format*. https://source.android.com/docs/core/ota/apex
- AOSP. *File-Based Encryption*. https://source.android.com/docs/security/features/encryption/file-based
- AOSP. *Metadata encryption*. https://source.android.com/docs/security/features/encryption/metadata
- AOSP. *Keystore*. https://source.android.com/docs/security/features/keystore
- AOSP. *KeyMint functions*. https://source.android.com/docs/security/features/keystore/implementer-ref
- AOSP. *Build SELinux*. https://source.android.com/docs/security/features/selinux/build
- AOSP. *Policy compatibility (SELinux)*. https://source.android.com/docs/security/features/selinux/compatibility
- AOSP. *VNDK overview*. https://source.android.com/docs/core/architecture/vndk
- AOSP. *Vendor interface object (VINTF)*. https://source.android.com/docs/core/architecture/vintf/objects
- AOSP. *Compatibility matrixes*. https://source.android.com/docs/core/architecture/vintf/comp-matrices
- AOSP. *Matching rules*. https://source.android.com/docs/core/architecture/vintf/match-rules
- AOSP. *FCM lifecycle*. https://source.android.com/docs/core/architecture/vintf/fcm
- AOSP. *Runtime resource overlays*. https://source.android.com/docs/core/runtime/rros
- AOSP. *Diagnose native crashes*. https://source.android.com/docs/core/tests/debug/native-crash
- AOSP. *Implement A/B updates*. https://source.android.com/docs/core/ota/ab/ab_implement
- AOSP. *init/README.md*. https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/README.md
- AOSP. *rootdir/init.rc*. https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/rootdir/init.rc
- AOSP. *init/selinux.cpp*. https://raw.githubusercontent.com/aosp-mirror/platform_system_core/master/init/selinux.cpp
- AOSP. *init/builtins.cpp*. https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/builtins.cpp
- AOSP. *fs_mgr.cpp*. https://android.googlesource.com/platform/system/core/+/refs/heads/main/fs_mgr/fs_mgr.cpp
- AOSP. *bootanimation/bootanim.rc*. https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/cmds/bootanimation/bootanim.rc
- AOSP. *BootAnimation.cpp*. https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/cmds/bootanimation/BootAnimation.cpp
- AOSP. *DropBoxManagerService.java*. https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/DropBoxManagerService.java
- AOSP. *Watchdog.java*. https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/services/core/java/com/android/server/Watchdog.java
- AOSP. *apexd.cpp*. https://android.googlesource.com/platform/system/apex/+/refs/heads/main/apexd/apexd.cpp
- AOSP. *odsign_main.cpp*. https://android.googlesource.com/platform/system/security/+/refs/heads/main/ondevice-signing/odsign_main.cpp
- AOSP. *logcat.cpp*. https://android.googlesource.com/platform/system/logging/+/refs/heads/main/logcat/logcat.cpp
- AOSP. *bootimg.h (android17-release)*. https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/android17-release/include/bootimg/bootimg.h
- LineageOS. *SurfaceFlinger.cpp @ lineage-24.0*. https://raw.githubusercontent.com/LineageOS/android_frameworks_native/lineage-24.0/services/surfaceflinger/SurfaceFlinger.cpp
- LineageOS. *ISurfaceComposer.aidl @ lineage-24.0*. https://raw.githubusercontent.com/LineageOS/android_frameworks_native/lineage-24.0/libs/gui/aidl/android/gui/ISurfaceComposer.aidl
- LineageOS. *system/sepolicy/Android.bp @ lineage-24.0*. https://raw.githubusercontent.com/LineageOS/android_system_sepolicy/lineage-24.0/Android.bp
- Linux Kernel. *kernel/module/main.c (v6.12)*. https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/module/main.c
- Linux Kernel. *kernel/module/version.c (v6.12)*. https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/module/version.c
- Linux Kernel. *kernel/module/internal.h (v6.12)*. https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/module/internal.h
- Linux Kernel. *init/main.c (v6.12)*. https://raw.githubusercontent.com/torvalds/linux/v6.12/init/main.c
- Linux Kernel. *ramoops oops/panic logger*. https://docs.kernel.org/admin-guide/ramoops.html
- Linux Kernel. *Bootconfig admin guide*. https://www.kernel.org/doc/html/latest/admin-guide/bootconfig.html
- Linux Kernel. *Building External Modules*. https://docs.kernel.org/kbuild/modules.html
- LineageOS. *Android Debugging Crash Course*. https://lineageos.org/engineering/HowTo-Debugging/
- AlanHC. *Android Vendor 升级要跨过的四道墙*. https://alanhc.github.io/til/docs/til-android-vendor-upgrade

---

## 待完善事项

本报告在执行过程中经历了审稿—修订循环，以下问题未能完全闭合，如实列出：

**1. 第 4 章与第 5 章的分歧：已由 init 的 builtin 语义解开**

初稿阶段的分歧是：动画在播能否证明 `/data` 已挂载。表面上看，SurfaceFlinger 属 `class core animation`、`class_start core` 只在 `on boot`、而 `on boot` 是 `late-init` 末位，似乎可推出"动画 ⇒ `post-fs-data` 已完成"。但这条推理漏了一个关键区分——**init 对"命令失败"与"属性等待"的处理语义完全不同**：

- **`mount_all` 失败不中止队列。** `do_mount_all` 把 `fs_mgr_mount_all()` 的返回码交给 `queue_fs_event()`，而后者只在 `FS_MGR_MNTALL_DEV_NEEDS_RECOVERY` 这一个返回码上 `reboot_into_recovery()`；`FS_MGR_MNTALL_FAIL` 没有显式分支，落入末尾的 `return Error()`，init 的 builtin 框架对返回 Error 的命令是**记录后继续执行后续命令**（[builtins.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/builtins.cpp)）。
- **`wait_for_prop` 未满足时队列不推进。** 机制分三处可查证：`PropWaiterState::StartWaiting()` 只记录待等属性并起计时器、**本身不阻塞**；init 主循环在 `MightBeWaiting()` 为真时**跳过** `am.ExecuteOneCommand()`，队列因此停住；属性变化由属性线程经 `PropertyChanged()` → `CheckAndResetWait()` 匹配后，用 **eventfd** 唤醒 init 主线程（[init.cpp](https://android.googlesource.com/platform/system/core/+/refs/heads/main/init/init.cpp)）。

  **这套设计本身反证了阻塞语义**：源码注释明确记录，旧方案"waited on property changes with a blocking socket … **it was easy to fill that socket and deadlock the system**"，故改为属性线程直接处理 + eventfd 唤醒。若等待期间主循环不停，就不需要专门设计唤醒机制。

  **证据层级**：实现层——`MightBeWaiting()` 守卫与 eventfd 唤醒都是具体实现，AOSP 改写即需重核。

由此得到可判定的分界：

| 假设 | 失败形态 | 与"动画在播"是否相容 | 结论 |
|---|---|---|---|
| `/data` 挂载失败（key blob version binding） | `mount_all` 返回 FAIL → init 记录后继续 → 后续命令逐个失败但队列推进 → `on boot` 到达、SF 启动、动画开播；而 zygote/system_server 因无 `/data` 起不来 | **相容** | **不排除，仍是首要候选** |
| KeyMint 与 vold 死锁 | init 卡在 `late-fs` → `on boot` 不到达 → 无动画 | 不相容 | 排除（死锁形态） |
| apexd 未跑完（`apexd.status` 停在 `starting`） | `post-fs-data` 阻塞在 `wait_for_prop` → 无动画 | 不相容 | 排除 |
| odsign 未跑完（`verification.done` 未置位） | `zygote-start` 阻塞在 `wait_for_prop` → 无动画 | 不相容 | 排除 |

**这同时纠正了报告初稿里一处错误表述**：曾写"`userdata` 无 `nofail` 且走 metadata 加密路径，故 `/data` 挂载失败**必然阻断启动**"。准确说法是"会使 `mount_all` 返回 FAIL，init 记录后继续推进"——**正因为它不阻断，才会出现"卡动画"而不是 bootloop**。

**一处必须点明的反直觉推论：闸门放行 ≠ 闸门后的工作成功。**

`apexd.cpp` 的 `OnAllPackagesActivated()` 并不检查激活是否成功——非 bootstrap 模式下它无条件 `SetProperty(gConfig->apex_status_sysprop, kApexStatusActivated)`；而 `OnStart()` 的失败处理走 `RevertActiveSessionsAndReboot()` 或 `ActivateMissingApexes()`，**从不把 `apexd.status` 设为 `failed`**（该属性只有 `starting` / `activated` / `ready` 三个值）（[apexd.cpp](https://android.googlesource.com/platform/system/apex/+/refs/heads/main/apexd/apexd.cpp)）。

因此 `wait_for_prop apexd.status activated` 这道闸门**即使 `/data/apex` 完全不可访问也会放行**——它表达的是"激活阶段结束"，不是"激活成功"。同理，odsign 的 scope_guard 也会在失败时置位 `verification.done=1`。

**这带来一个重要的判读纪律**：`apexd.status=activated` 与 `odsign.verification.done=1` 都**不能**用来证明 `/data` 侧健康。它们只证明"闸门已放行"，而放行本身可能是失败路径的结果。

**仍未闭合的三点**（决定上述分层是否成立，需实测或源码复核）：

1. apexd 在无 `/data` 时能否仅凭 `/system/apex` 完成激活并置位 `activated`；
2. odsign 的 scope_guard 是否覆盖"取密钥失败"这条路径（若它在装 scope_guard 之前就 return，会阻塞 `zygote-start`，退化为无动画）；
3. **`start_waiting_for_property` 的阻塞实现**——若它走共享内存 futex（Android 8 起属性快路径），则"等待方阻塞、设值方直接唤醒"成立，不产生自锁；若它走 socket 到 `property_service`，则"init 阻塞导致属性设不上"的悖论成立，`wait_for_prop` 阻塞这一支点需整体重估。**这一条同时是第 1、4、5 章的共同软肋**，应优先复核。

前两条的判据分别是一次 TWRP 快照中的 `/data/misc/bootanim` 是否存在、`/data/misc/odsign/` 内容是否完整。

**E1 的观测点必须钉死**：判别信号落在"**`/data` 是否可挂载**"，而不是"apexd 是否 `activated`"。`apexd.status` 由 `OnAllPackagesActivated()` 无条件置位、零判别力（见上），用它当判据会得出反向结论。

**2. 三处判据依赖推断而非源码直证**

- `/metadata/apex/sessions` 非空 ⇒ apexd 激活中途失败（按目录命名与创建位置推断，待实测确认）
- `/data/system/environ/classpath` 的 mtime 可作启动时间轴（未核实该文件是否每轮必写）
- `wait_for_prop` 的队列阻塞语义（同上第 1 条）

**3. 三处"审稿意见经复核不成立"的记录**

- `early_mod_check()` 的黑名单位置：审稿人主张在 `check_modinfo()` 内，经作者在 v6.12 / v6.12.69 / v6.17 三版源码核对，确认 `blacklisted()` 位于函数首步，原稿正确，审稿意见撤回
- `/data/dalvik-cache` 的 `encryption=Require` 归属：审稿人主张属 fstab 标志，经核对 `encryption=` 是 init 语言 `mkdir` 的选项（语法见 init/README.md），作者正确
- `signature_size` 的作用范围：修订员曾以"文档未表述"为由删除原推断，作者复现 AOSP 原文后确认该表述有官方出处，已恢复

**4. 审稿轮次的实际执行情况**

- 第 1 章：1 轮 REVISE 已闭环
- 第 2 章：1 轮 REVISE 已闭环，第 2 轮豁免（未做第 2 轮复核，判其 2.2 措辞达标的依据是修订说明中的转述文本，非全文重审）
- 第 3 章：定稿后未走独立审稿轮，由主理人逐条核对
- 第 4 章：1 轮 REVISE 已闭环，后续两轮修正（CE/DE 判读、ctime 判据撤回）由主理人与作者交叉核对完成
- 第 5 章：1 轮 REVISE 已闭环，后续经 **v3—v11** 共 9 轮自我更正（含四次判断反转：ctime 判据、死锁主候选、SF 时序排除、中性证据）

**5. 本项目数据的可复现性说明**

报告中的实测数字（内核 sha256、模块计数、ramdisk 体积、CRC 值）均来自本项目构建产物与原厂固件的直接测量，测量方法与脚本存于项目仓库 `scripts/` 目录。但**部分测量未保留原始输出文件**（如 `fastboot getvar all` 的完整快照采于恢复原厂之后，仅可作变量格式示例），复现时需重新采集。

---

> 本报告由 AI 深度研究团队生成，重要决策请经专业人员核验。所有引用来源请用户在重要场景下二次核验时效性与真实性。
