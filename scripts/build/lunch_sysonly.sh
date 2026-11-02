#!/bin/bash
# lunch_sysonly.sh —— 切到 sysonly 变体的 lunch 目标并导出环境
cd /root/android/lineage || exit 9
source build/envsetup.sh
lunch lineage_pandora_sysonly-bp4a-userdebug
