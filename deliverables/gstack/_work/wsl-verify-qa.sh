#!/bin/bash
# 复核 qa-lead 报告的三条新发现
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks

L="$STAGE/vb/los/lib/modules"
S="$STAGE/vb/stock/lib/modules"

echo "########## 1. modules.load.recovery 两侧是否相同 ##########"
for side in los stock; do
  f="$STAGE/vb/$side/lib/modules/modules.load.recovery"
  if [ -f "$f" ]; then
    printf "  %-5s %6s B  sha256=%s  条目=%s 唯一=%s\n" "$side" "$(stat -c%s "$f")" \
      "$(sha256sum "$f" | cut -c1-16)" "$(grep -c . "$f")" "$(awk '{print $1}' "$f" | sort -u | wc -l)"
  else
    echo "  $side: 无此文件"
  fi
done

echo
echo "########## 2. vendor_dlkm 8 条悬空：文件到底在哪 ##########"
for m in bcl_soc.ko binder_prio.ko common.ko mca_pbb.ko miwill.ko nvmem_qfprom.ko qcom_cache_allocation.ko quic.ko; do
  in_vb=$([ -f "$L/$m" ] && echo Y || echo -)
  in_vd=$(ls "$STAGE"/vb/*/lib/modules/"$m" 2>/dev/null | head -1)
  ref_vb=$(grep -lx "$m" "$L/modules.load" 2>/dev/null | head -1)
  printf "  %-26s vendor_boot文件=%s  vendor_boot清单=%s\n" "$m" "$in_vb" "${ref_vb:-否}"
done

echo
echo "########## 3. system_dlkm flatten 与 版本化 清单是否同一份 ##########"
FL="$STAGE/los_sd_flat.load"; VE="$STAGE/los_sd_ver.load"
mkdir -p "$STAGE/mnt/los_sd"
mountpoint -q "$STAGE/mnt/los_sd" || mount -o loop,ro "$IMGS/system_dlkm.img" "$STAGE/mnt/los_sd" || exit 9
cp "$STAGE/mnt/los_sd/flatten/lib/modules/modules.load" "$FL"
cp "$STAGE/mnt/los_sd/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k/modules.load" "$VE"
echo "  flatten  条目=$(grep -c . "$FL")"
echo "  版本化   条目=$(grep -c . "$VE")"
echo "  只在 flatten 有:"; comm -23 <(sed 's#.*/##' "$FL" | sort -u) <(sed 's#.*/##' "$VE" | sort -u) | sed 's/^/     /'
echo "  只在 版本化 有:"; comm -13 <(sed 's#.*/##' "$FL" | sort -u) <(sed 's#.*/##' "$VE" | sort -u) | sed 's/^/     /'
echo "  内核 TLS 配置: $(grep -E '^#? ?CONFIG_TLS' "$WORK/los_kconfig.txt" | head -2)"
umount "$STAGE/mnt/los_sd" 2>/dev/null
