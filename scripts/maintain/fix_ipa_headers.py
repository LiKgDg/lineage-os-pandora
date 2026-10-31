#!/usr/bin/env python3
"""修复预编译内核设备上 libipanat / ipacm 找不到 linux/msm_ipa.h。

背景：
  hardware/qcom-caf/common/Android.bp 里的 qti_ipa_kernel_headers 走
  generated_kernel_header_defaults -> generated_kernel_includes，后者要跑
  内核源码的 `make headers_install`。预编译内核设备没有内核源码，导出目录为空。

  dataipa 项目自带正确的 UAPI 头：
    drivers/platform/msm/include/uapi/linux/msm_ipa.h
  且该头自带 #ifndef __KERNEL__ 保护，用户态可直接用。

做法：
  1. 在 drivers/platform/msm/ 下新建 Android.bp，定义 qti_ipa_kernel_headers_dp
     导出 include/uapi
  2. 把 3 处 header_libs 里的 "qti_ipa_kernel_headers" 追加新模块

用法:
  fix_ipa_headers.py [--revert]
"""
import os
import sys

ROOT = "/root/los24/hardware/qcom-caf/sm8850"

BP_NEW = os.path.join(ROOT, "dataipa/drivers/platform/msm/Android.bp")
CONSUMERS = [
    os.path.join(ROOT, "dataipa/ipanat/Android.bp"),
    os.path.join(ROOT, "data-ipa-cfg-mgr/ipacm/Android.bp"),
]

OLD = '"qti_ipa_kernel_headers"]'
NEW = '"qti_ipa_kernel_headers", "qti_ipa_kernel_headers_dp"]'

BP_CONTENT = """// pandora: 预编译内核设备没有内核源码，hardware/qcom-caf/common 里的
// qti_ipa_kernel_headers 依赖 headers_install 生成，导出目录为空。
// 这里直接导出项目自带的 UAPI 头（自带 #ifndef __KERNEL__ 保护）。
cc_library_headers {
    name: "qti_ipa_kernel_headers_dp",
    export_include_dirs: ["include/uapi"],
    vendor: true,
    recovery_available: true,
}
"""


def main():
    revert = "--revert" in sys.argv

    if revert:
        if os.path.exists(BP_NEW):
            os.remove(BP_NEW)
            print("REMOVED %s" % BP_NEW)
        for p in CONSUMERS:
            t = open(p, encoding="utf-8").read()
            if NEW in t:
                open(p, "w", encoding="utf-8").write(t.replace(NEW, OLD))
                print("REVERTED %s" % p)
        return 0

    if os.path.exists(BP_NEW):
        print("SKIP: %s exists" % BP_NEW)
    else:
        with open(BP_NEW, "w", encoding="utf-8") as f:
            f.write(BP_CONTENT)
        print("CREATED %s" % BP_NEW)

    total = 0
    for p in CONSUMERS:
        t = open(p, encoding="utf-8").read()
        n = t.count(OLD)
        if n:
            open(p, "w", encoding="utf-8").write(t.replace(OLD, NEW))
            print("PATCHED %s (%d 处)" % (os.path.basename(os.path.dirname(p)), n))
            total += n
        else:
            print("SKIP %s (无匹配)" % p)
    print("共修补 %d 处 header_libs" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
