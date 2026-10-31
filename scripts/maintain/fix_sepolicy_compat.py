#!/usr/bin/env python3
"""为 treble_sepolicy_tests_202604 补 SELinux 兼容性忽略清单。

背景：
  vendor sepolicy（来自 blobs 与设备树）新增了一批 public type，
  但没有在 private/compat/<ver>/<ver>.ignore.cil 里登记，
  treble_sepolicy_tests 因此失败：

    SELinux: The following public types were found added to the policy
    without an entry into the compatibility mapping file(s)

做法：
  在 device/xiaomi/sm8850-common/sepolicy/private/compat/202604/ 下
  新建 202604.ignore.cil，把这些类型加入 new_objects 集合。
  这是 AOSP 官方推荐的处理方式（见报错里给的两个 review 链接），
  语义上表示「这些类型没有历史对应物，无需映射」。

用法:
  fix_sepolicy_compat.py [--revert]
"""
import os
import sys

BASE = "/root/los24/device/xiaomi/sm8850-common/sepolicy/private/compat/202604"
TARGET = os.path.join(BASE, "202604.ignore.cil")

# 来自 treble_sepolicy_tests 的完整报错清单
TYPES = """
hal_touchfeature_xiaomi_default
hal_touchfeature_xiaomi_default_exec
hal_touchfeature_xiaomi_service
iso9660
qsguard
udf
usb_uvc_config_prop
vendor_afp_prop
vendor_bt_prop
vendor_dataservice_app
vendor_display_notch_prop
vendor_dpmd
vendor_dpmtcm_socket
vendor_dun-server
vendor_elabel_data_file
vendor_fm_app
vendor_gppservice
vendor_hal_atfwd_hwservice
vendor_hal_displayconfig_service
vendor_hal_qvirt_service
vendor_hal_qvirtservice_qti
vendor_hal_systemhelper_aidl_service
vendor_hal_systemhelper_hwservice
vendor_hal_telephony_service
vendor_location_app
vendor_mm_parser_prop
vendor_mmi_sys
vendor_perfservice
vendor_persist_camera_prop
vendor_persist_dpm_prop
vendor_persist_nfc_prop
vendor_persist_ntn_prop
vendor_persist_rcs_prop
vendor_persist_tcm_prop
vendor_qcc_app
vendor_qcc_authmgr_app
vendor_qcc_lmtp_app
vendor_qcc_netstat_app
vendor_qcc_trd
vendor_qcc_utils_app
vendor_qccsyshal_hwservice
vendor_qesdk_service
vendor_qspmsvc
vendor_qtelephony
vendor_qvirtmgr
vendor_qvirtmgr_prop
vendor_qvrd
vendor_seempd
vendor_seempdw_socket
vendor_sigmahal_hwservice
vendor_smcinvoke_device
vendor_sys_qti_display
vendor_sys_video_prop
vendor_systemhelper_app
vendor_usta_app_service
vendor_vpsservice
vendor_wfd_app
vendor_wfdservice
vendor_wlc_prop
vendor_wlc_public_prop
xtra_control_prop
""".split()


def build_content():
    head = (
        ";; new_objects - a collection of types that have been introduced that have no\n"
        ";;   analogue in older policy. Thus, we do not need to map these types to\n"
        ";;   previous ones. Add here to pass checkapi/treble compatibility tests.\n"
        "(type new_objects)\n"
        "(typeattribute new_objects)\n"
        "(typeattributeset new_objects\n"
        "  ( new_objects\n"
    )
    body = "".join("    %s\n" % t for t in TYPES)
    return head + body + "  ))\n"


def main():
    if "--revert" in sys.argv:
        if os.path.exists(TARGET):
            os.remove(TARGET)
            try:
                os.rmdir(BASE)
            except OSError:
                pass
            print("REMOVED %s" % TARGET)
        else:
            print("SKIP: not present")
        return 0

    os.makedirs(BASE, exist_ok=True)
    with open(TARGET, "w", encoding="utf-8") as f:
        f.write(build_content())
    print("WROTE %s (%d types)" % (TARGET, len(TYPES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
