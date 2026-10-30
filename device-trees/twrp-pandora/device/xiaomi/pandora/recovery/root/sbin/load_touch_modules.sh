#!/system/bin/sh
#
# Recovery bring-up helper: try to load touchscreen kernel modules when
# the normal module autoload path misses them.
#

log_msg() {
    echo "[touch-loader] $1" > /dev/kmsg 2>/dev/null
}

mount_vendor_dlkm() {
    mkdir -p /vendor_dlkm
    if [ -d /vendor_dlkm/lib/modules ]; then
        return 0
    fi

    mount /dev/block/by-name/vendor_dlkm /vendor_dlkm >/dev/null 2>&1 || return 1
    [ -d /vendor_dlkm/lib/modules ]
}

insmod_one() {
    mod_path="$1"
    [ -f "$mod_path" ] || return 1
    if insmod "$mod_path" >/dev/null 2>&1; then
        log_msg "loaded $(basename "$mod_path")"
        return 0
    fi
    return 1
}

log_msg "start"
if ! mount_vendor_dlkm; then
    log_msg "failed to mount vendor_dlkm"
    exit 0
fi

insmod_one "/vendor_dlkm/lib/modules/xiaomi_touch.ko" || log_msg "missing xiaomi_touch.ko"
insmod_one "/vendor_dlkm/lib/modules/synaptics_tcm2.ko" || log_msg "missing synaptics_tcm2.ko"
log_msg "done"
