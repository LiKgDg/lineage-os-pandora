#!/bin/bash
echo "===== fsck.erofs help ====="
fsck.erofs --help 2>&1 | head -40
echo
echo "===== whoami / id ====="
id
echo
echo "===== loop devices ====="
ls /dev/loop* 2>&1 | head -5
