#!/bin/bash
echo "== tools =="
for t in fsck.erofs dump.erofs erofsfuse debugfs e2cp simg2img lpunpack unzip python3 modinfo file xxd od; do
  p=$(command -v "$t" 2>/dev/null)
  if [ -n "$p" ]; then echo "OK   $t -> $p"; else echo "MISS $t"; fi
done
echo "== kernel =="
uname -r
