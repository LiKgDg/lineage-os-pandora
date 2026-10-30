# Recovery 模式切换补丁（rc-mode）

设备：Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）
适用：LineageOS 23.2 recovery（`recovery-pandora-dualkey.img` 系列）
日期：2026-10-30

---

## 一、作用范围

补丁只改 **recovery ramdisk 内部**，不触碰 boot / vendor_boot / system：

| 文件 | 作用 |
|---|---|
| `device/xiaomi/pandora/recovery/root/system/bin/rc-mode` | 用户态入口，校验参数、调度切换、带超时安全网 |
| `device/xiaomi/pandora/recovery/root/init.recovery.usb.rc` | 每个 USB 配置分支前加 `write UDC "none"`，强制主机重新枚举 |
| `device/xiaomi/pandora/recovery/root/init.recovery.qcom.rc` | 增加 `sys.usb.config=fastboot/adb` 的确定性切换时序 |

不涉及：
- 正常系统启动流程（这些 rc 只在 recovery 里被 init 读取）
- 分区表、AVB、super 布局
- adbd 的认证策略（由 `ro.adb.secure` 控制，本设备为 `0`）

---

## 二、触发条件

1. 设备处于 **recovery**，且 adb 已连上并授权
   （`adb devices` 显示 `<serial>  recovery`）。
   本设备 `ro.adb.secure=0`，recovery 起来即自动授权；若换成安全构建，
   需要用户在 recovery 菜单里手动 Enable ADB。
2. 命令以 root 执行（recovery 的 adbd 默认 root）。
3. 只在 `ro.boot.mode` 为 recovery 时有意义；正常系统里没有 `fastbootd`、
   也没有这套 USB gadget 配置，脚本会因 `setprop` 后状态不变而走安全网退回。

---

## 三、支持的目标模式

| 参数 | 是否重启 | USB 描述符 | 说明 |
|---|---|---|---|
| `fastboot` / `fbtd` | 否 | `18d1:4ee0` | 切到 fastbootd，可直接 `fastboot flash` 逻辑分区 |
| `adb` | 否 | `18d1:d001` | 从 fastbootd 切回 adb |
| `sideload` | 是 | `18d1:d001` | 写 BCB `boot-sideload` 后重启，recovery 自动起 minadbd |
| `rescue` | 是 | — | 写 BCB `boot-rescue` |
| `reboot` | 是 | — | 普通重启 |
| `poweroff` | 是 | — | 关机 |
| `status` | 否 | — | 打印 `sys.usb.state` / `sys.usb.config` / `sys.usb.ffs.ready` / 两个服务状态 / 槽位 |

> `sideload` 只能重启进入：AOSP recovery 的 sideload 是由 **recovery 主进程**
> 调用 `apply_from_adb()` fork `minadbd` 启动的，没有可供 init 触发的服务项，
> 因此无法在运行中热切。`adb reboot sideload` 走的就是同一条 BCB 路径。

---

## 四、预期行为与交互流程

### 4.1 切到 fastbootd（热切）

```
$ adb shell rc-mode fastboot
已调度切换到 fastboot，adb 即将断开（USB 会重新枚举）
```

设备侧实际顺序（全部由 init 执行，与 adb 会话是否存活无关）：

```
1. rc-mode 脱离 adb shell（nohup 自举），避免 adbd 被停后收到 SIGHUP 中断
2. setprop sys.usb.config none
     → write /config/usb_gadget/g1/UDC "none"      # 解绑 gadget
     → stop adbd
     → setprop sys.usb.ffs.ready 0
     → rm b.1/f1 f2 f3
3. sleep 1
4. setprop sys.usb.config fastboot
     → stop adbd（幂等）
     → setprop sys.usb.ffs.ready 0                 # 关键：清零共享标志
     → start fastbootd
5. fastbootd 打开 /dev/usb-ffs/fastboot，置 sys.usb.ffs.ready=1
6. init.recovery.usb.rc 的 fastboot 分支触发：
     write UDC "none"                              # 再解绑一次，保证干净
     write configs/b.1/strings/0x409/configuration "fastboot"
     write idVendor 0x18D1 / idProduct 0x4EE0
     symlink functions/ffs.fastboot → configs/b.1/f1
     write UDC ${sys.usb.controller}                # 绑定 → 主机重新枚举
7. setprop sys.usb.state fastboot
```

主机侧表现：

```
$ fastboot devices
fd3af370   fastboot
$ fastboot getvar is-logical:system
is-logical:system: yes
```

### 4.2 切回 adb

```
$ fastboot reboot recovery          # 或从 fastbootd 退出
$ adb shell rc-mode adb
```

对称执行：`stop fastbootd` → 清零 `ffs.ready` → `start adbd` → adbd 置位后绑定
`18d1:d001`。

### 4.3 进入 sideload

```
$ adb shell rc-mode sideload
重启进入 sideload…
$ adb devices
fd3af370   sideload
$ adb sideload package.zip
```

### 4.4 安全网

`rc-mode` 在切换后最多等 8 秒；若 `sys.usb.state` 未变成目标值，自动执行
`none → adb` 退回，并写 log：

```
logger -t rc-mode "switch to fastboot TIMEOUT after 8s, state=..."
```

目的是**任何情况下都不把设备留在"USB 设备消失"的状态**。

---

## 五、这次踩到的坑（重要）

### 现象

第一版补丁只加了「写 UDC 前先解绑」，结果：

- `rc-mode fastboot` → 电脑上 **USB 设备整个消失**（adb、fastboot 都没有）
- 用户从 recovery 菜单**手动**进 fastbootd → 同样 USB 消失

### 根因

`sys.usb.ffs.ready` 是 **adb 与 fastboot 共用**的全局标志，不是"某个功能就绪"。
adbd 存活期间它一直是 `1`。因此：

```
setprop sys.usb.config fastboot
  → 此时 ffs.ready 仍为 1（adbd 设的）
  → init.recovery.usb.rc 的 fastboot 分支"立刻"触发
  → 我加的 write UDC "none" 把 gadget 解绑
  → 接着 symlink ffs.fastboot 并 write UDC 绑定
  → 但 fastbootd 还没启动，ffs.fastboot 没有任何描述符
  → 主机枚举到一个空设备 / 枚举失败
  → 随后 start fastbootd 才执行，ffs 已被占用，fastbootd 起不来
  → gadget 停在解绑状态：电脑上什么都看不到
```

补丁之前之所以"只是没反应"而不是"USB 消失"，是因为当时 `write UDC`
写入的是同一个已绑定值，内核视为 no-op，gadget 一直留在 adb 配置上——
所以表现为「fastbootd 在跑，但主机只看到 adb」。

### 修复

在 `init.recovery.qcom.rc` 里给切换动作补上确定性时序：

```
on property:sys.usb.config=fastboot
    stop adbd
    setprop sys.usb.ffs.ready 0
    start fastbootd

on property:sys.usb.config=adb
    stop fastbootd
    setprop sys.usb.ffs.ready 0
    start adbd
```

这样 `ffs.ready=1` 只可能由**目标服务**置位，绑定 UDC 时描述符一定已就绪。
再加上 `rc-mode` 的 8 秒安全网，最坏情况也能退回 adb。

---

## 六、验证清单

| 项 | 方法 | 期望 |
|---|---|---|
| 脚本进镜像 | `adb shell ls -l /system/bin/rc-mode` | 存在且可执行 |
| 补丁进 ramdisk | `grep -c 'rc-mode: 解绑 UDC' /init.recovery.usb.rc` | 4 |
| 时序补丁 | `grep -c 'USB 模式切换的确定性时序' /init.recovery.qcom.rc` | 1 |
| 状态查询 | `adb shell rc-mode status` | 打印 6 行状态 |
| 热切 fastbootd | `adb shell rc-mode fastboot` → `fastboot devices` | 出现设备，`is-logical:system` 为 yes |
| 切回 adb | `fastboot reboot recovery` → `adb shell rc-mode adb` | `sys.usb.state=adb` |
| 安全网 | 人为让 fastbootd 起不来 | 8 秒后自动回 adb |
