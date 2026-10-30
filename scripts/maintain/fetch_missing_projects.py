#!/usr/bin/env python3
"""补齐 TWRP 源码树中缺失的项目。

repo 在当前树里无法正常 checkout（对象有、ref 没有、sync 直接跳过），
这里直接用 git 从镜像拉取并检出到工作区。

远端判定：
  name 以 android_ / twrp_ 开头  -> https://github.com/TWRP-Test/<name>  分支 twrp-16.0
  其它                            -> https://mirrors.bfsu.edu.cn/git/AOSP/<name>  标签 android-16.0.0_r1

用法：python3 fetch_missing_projects.py [--dry-run]
"""

import os
import subprocess
import sys

ROOT = "/root/twrp"
REPO = "/root/repo-tool/repo"
AOSP = "https://mirrors.bfsu.edu.cn/git/AOSP"
TWRP = "https://github.com/TWRP-Test"
TAG = "refs/tags/android-16.0.0_r1"
BRANCH = "refs/heads/twrp-16.0"

DRY = "--dry-run" in sys.argv


def run(cmd, cwd=None, check=False):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)


def list_projects():
    out = run([REPO, "list", "-f"], cwd=ROOT).stdout
    projects = []
    for line in out.splitlines():
        if " : " not in line:
            continue
        path, name = line.split(" : ", 1)
        path = path.strip()
        name = name.strip()
        if path.startswith(ROOT + "/"):
            path = path[len(ROOT) + 1:]
        projects.append((path, name))
    return projects


def is_twrp(name):
    return name.startswith("android_") or name.startswith("twrp_")


def gitdir_for(name):
    return os.path.join(ROOT, ".repo", "project-objects", name + ".git")


def fetch_and_checkout(path, name):
    gd = gitdir_for(name)
    if is_twrp(name):
        url, ref = f"{TWRP}/{name}", BRANCH
    else:
        url, ref = f"{AOSP}/{name}", TAG

    print(f"\n=== {path}  ({name})", flush=True)
    print(f"    url={url}  ref={ref}", flush=True)

    if DRY:
        return True

    if not os.path.isdir(gd):
        os.makedirs(gd, exist_ok=True)
        r = run(["git", "init", "--bare", gd])
        if r.returncode != 0:
            print(f"    init 失败: {r.stderr.strip()[:200]}", flush=True)
            return False

    r = run(["git", f"--git-dir={gd}", "fetch", "--depth=1", url, f"{ref}:{ref}"])
    if r.returncode != 0:
        print(f"    fetch 失败: {r.stderr.strip().splitlines()[-1][:200] if r.stderr.strip() else '?'}", flush=True)
        return False

    os.makedirs(os.path.join(ROOT, path), exist_ok=True)
    r = run(["git", f"--git-dir={gd}", f"--work-tree={os.path.join(ROOT, path)}",
             "checkout", "-f", ref])
    if r.returncode != 0:
        print(f"    checkout 失败: {r.stderr.strip()[:200]}", flush=True)
        return False

    print("    OK", flush=True)
    return True


def main():
    projects = list_projects()
    missing = [(p, n) for p, n in projects if not os.path.exists(os.path.join(ROOT, p))]
    print(f"项目总数 {len(projects)}，缺失 {len(missing)}")
    for p, n in missing:
        print(f"  MISS {p}  <- {n}")

    ok = fail = 0
    for p, n in missing:
        if fetch_and_checkout(p, n):
            ok += 1
        else:
            fail += 1

    print(f"\n完成：成功 {ok}，失败 {fail}")


if __name__ == "__main__":
    main()
