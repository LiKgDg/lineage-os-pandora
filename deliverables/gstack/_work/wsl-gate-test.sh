#!/bin/bash
# kmi-gate.sh 实测：LOS 现状 / stock 现状 / 方案 A 修复后 + 边界用例
# 注意：$? 必须在**没有管道**的地方取，否则拿到的是 tail/tee 的退出码。
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
G="$W/deliverables/gstack/_work/kmi-gate.sh"
S=/root/work/gstack/qa/sets
OUT=/root/work/gstack/qa
sed -i 's/\r$//' "$G"
bash -n "$G" || { echo "SYNTAX FAIL"; exit 9; }
echo "### 语法检查 OK"

echo
echo "############ 实测 1：LOS 现状（期望 FAIL） ############"
bash "$G" "$S/los-vb" "$S/los-vd" "$S/los-sd-flat"; echo "### exit=$?"

echo
echo "############ 实测 2：stock 现状（期望 PASS） ############"
bash "$G" "$S/stock-vb" "$S/stock-vd" "$S/stock-sd-flat"; echo "### exit=$?"

echo
echo "############ 实测 3：方案 A1 修复后（期望 PASS） ############"
bash "$G" "$S/fixed-vb" "$S/fixed-vd"; echo "### exit=$?"

echo
echo "############ 附 A：集合名去重（两个目录都叫 lib/modules）############"
rm -rf "$OUT/nametest"; mkdir -p "$OUT/nametest/los/lib/modules" "$OUT/nametest/stock/lib/modules"
cp "$S/los-vb/zram.ko" "$S/los-vb/zsmalloc.ko" "$OUT/nametest/los/lib/modules/" 2>/dev/null
cp "$S/stock-vb/zram.ko" "$S/stock-vb/zsmalloc.ko" "$OUT/nametest/stock/lib/modules/" 2>/dev/null
bash "$G" -q -n "$OUT/nametest/los/lib/modules" "$OUT/nametest/stock/lib/modules"; echo "### exit=$?"
echo "（上面汇总表两行的集合名应分别是 los/lib/modules 与 stock/lib/modules，不能都是 modules）"

echo
echo "############ 附 B：LOS system_dlkm 版本化目录 vs flatten 副本 ############"
bash "$G" -q "$S/los-sd-ver" "$S/los-sd-flat"; echo "### exit=$?"

echo
echo "############ 附 C：--no-load（CRC-only）############"
bash "$G" -n -q "$S/stock-sd-flat"; echo "### exit=$?"

echo
echo "############ 附 D：--strict-dup 下 stock 也 FAIL（原厂自带 263 重复）############"
bash "$G" -q --strict-dup "$S/stock-vd"; echo "### exit=$?"

echo
echo "############ 附 E：--strict-vermagic 下 LOS 也 FAIL（405 条旧 vermagic）############"
bash "$G" -q --strict-vermagic "$S/los-vb"; echo "### exit=$?"

echo
echo "############ 附 F：边界用例 ############"
mkdir -p "$S/empty"
bash "$G" -q "$S/empty" > "$OUT/e1.log" 2>&1; rc=$?
echo "空目录 exit=$rc"; tail -3 "$OUT/e1.log"
bash "$G" -q "$S/nope"  > "$OUT/e2.log" 2>&1; rc=$?
echo "不存在目录 exit=$rc"; tail -3 "$OUT/e2.log"
bash "$G" > /dev/null 2>&1; echo "无参数 exit=$?"
bash "$G" -x > /dev/null 2>&1; echo "未知选项 exit=$?"
bash "$G" -K /nonexistent.img "$S/stock-vb" > /dev/null 2>&1; echo "内核不存在 exit=$?"

echo
echo "############ 附 G：-K 抓半迁移（本次事故形态）############"
BOOT="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images/boot.img"
echo "-- G1 正例：期望 KMI 与内核一致 → 应 PASS --"
bash "$G" -q -K "$BOOT" "$S/stock-vb" "$S/stock-vd"; echo "### exit=$?"
echo "-- G2 反例：把期望 KMI 设成旧世代 6.12.23-android16-5 → 必须 FAIL --"
bash "$G" -q -k 6.12.23-android16-5 -c 0xe976b219 -K "$BOOT" "$S/stock-vb" 2>&1 | grep -E "内核 banner|门禁结果|CRC 一致"; echo "### exit=${PIPESTATUS[0]}"
