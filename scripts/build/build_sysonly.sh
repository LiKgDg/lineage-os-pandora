#!/bin/bash
cd /root/android/lineage || exit 9
export JAVA_HOME=/root/android/lineage/prebuilts/jdk/jdk21/linux-x86
export PATH="$JAVA_HOME/bin:/root/android/lineage/prebuilts/build-tools/linux-x86/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_pandora_sysonly-bp4a-userdebug >/dev/null 2>&1
timeout 500 m systemimage systemextimage productimage -j12 >> /root/sysonly_build.log 2>&1
rc=$?
echo "rc=$rc"
ls -la out/target/product/pandora/system.img out/target/product/pandora/system_ext.img out/target/product/pandora/product.img 2>/dev/null || echo "(尚无镜像)"
tail -2 /root/sysonly_build.log
