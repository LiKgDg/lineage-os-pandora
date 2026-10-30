#!/bin/bash
cd /root/android/lineage || exit 9
source build/envsetup.sh
lunch lineage_pandora_sysonly-bp4a-userdebug
