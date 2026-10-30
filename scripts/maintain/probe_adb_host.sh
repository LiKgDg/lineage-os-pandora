#!/bin/bash
# 探测 WSL 到 Windows adb server 的可用地址
for host in 127.0.0.1 192.168.31.240 172.31.192.1; do
  printf "%-18s " "$host"
  out=$(ADB_SERVER_SOCKET=tcp:$host:5037 timeout 8 adb devices 2>&1 | tail -2 | tr '\n' ' ')
  echo "$out"
done
