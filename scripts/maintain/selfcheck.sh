#!/bin/bash
# =============================================================================
# selfcheck.sh —— 仓库自检：语法 / 换行 / 元数据 / 文档覆盖
#
# 为什么需要
#   仓库里有 106 个 .sh 和 42 个 .py，但其中 30 多个没有任何文档引用。
#   代码本身是健康的（2026-11-02 全量跑过：语法错 0、CRLF 0），
#   问题是这些检查一直是手工做的、结论只存在于对话里，下次没人能复跑。
#   这个脚本把它们固化下来，并顺带生成脚本索引。
#
# 用法
#   bash scripts/maintain/selfcheck.sh              # 体检，有问题则 exit 1
#   bash scripts/maintain/selfcheck.sh --index      # 顺带重写 docs/scripts-index.md
#   bash scripts/maintain/selfcheck.sh --quiet      # 只报错，不打明细
#
# 检查项
#   C1  bash -n 全部 .sh
#   C2  python 语法解析全部 .py
#   C3  已跟踪文本文件的 CRLF（仓库约定全 LF，见 .gitattributes）
#   C4  **/lineage.dependencies 的 JSON 合法性
#   C5  发布用的 device-trees 目录必须有 LICENSE（Apache-2.0 §4(a)）
#   C6  脚本索引是否过期（仅在 --index 时重写）
#
# 退出码
#   0 全部通过
#   1 有检查项失败
#   2 前置不满足（不在仓库根 / 缺 git）
# =============================================================================
set -u

QUIET=0; WRITE_INDEX=0
while [ $# -gt 0 ]; do
    case "$1" in
        --index) WRITE_INDEX=1; shift ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 2
[ -d .git ] || { echo "ERROR: 不在仓库根" >&2; exit 2; }

FAIL=0
ok()   { [ "$QUIET" -eq 1 ] || echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
info() { [ "$QUIET" -eq 1 ] || echo "$*"; }
hr()   { [ "$QUIET" -eq 1 ] || printf '%s\n' "────────────────────────────────────────────────────────────"; }

PY=${PYTHON:-python}
command -v "$PY" >/dev/null 2>&1 || PY=python3

# ---- C1: bash -n ------------------------------------------------------------
hr
info "[C1] shell 语法（bash -n）"
N_SH=0; BAD_SH=0
while IFS= read -r f; do
    N_SH=$((N_SH + 1))
    if ! bash -n "$f" 2>/dev/null; then bad "语法错误：$f"; BAD_SH=$((BAD_SH + 1)); fi
done < <(git ls-files '*.sh')
[ "$BAD_SH" -eq 0 ] && ok "$N_SH 个 .sh 全部通过"

# ---- C2: python 语法 --------------------------------------------------------
info "[C2] python 语法"
N_PY=0; BAD_PY=0
while IFS= read -r f; do
    N_PY=$((N_PY + 1))
    if ! "$PY" -c "import ast,io,sys; ast.parse(io.open(sys.argv[1],encoding='utf-8').read())" "$f" 2>/dev/null; then
        bad "语法错误：$f"; BAD_PY=$((BAD_PY + 1))
    fi
done < <(git ls-files '*.py')
[ "$BAD_PY" -eq 0 ] && ok "$N_PY 个 .py 全部通过"

# ---- C3: CRLF ---------------------------------------------------------------
# 不能用 grep -c $'\r'：在这个环境里它返回的是总行数，不是 CR 命中数。
info "[C3] 换行符（应有 0 个 CRLF）"
N_CRLF=0
while IFS= read -r f; do
    c=$(git cat-file -p "HEAD:$f" 2>/dev/null | "$PY" -c "import sys;d=sys.stdin.buffer.read();print(d.count(b'\r\n'))" 2>/dev/null || echo 0)
    if [ "${c:-0}" -gt 0 ]; then bad "含 CRLF：$f（$c 行）"; N_CRLF=$((N_CRLF + 1)); fi
done < <(git ls-files '*.sh' '*.py' '*.mk' '*.md' '*.json' '*.txt')
[ "$N_CRLF" -eq 0 ] && ok "全部文本文件均为 LF"

# ---- C4: lineage.dependencies ----------------------------------------------
info "[C4] lineage.dependencies（JSON 合法性）"
N_DEP=0; BAD_DEP=0
while IFS= read -r f; do
    N_DEP=$((N_DEP + 1))
    if ! "$PY" -c "import json,sys; json.load(open(sys.argv[1],encoding='utf-8'))" "$f" 2>/dev/null; then
        bad "JSON 非法：$f"; BAD_DEP=$((BAD_DEP + 1))
    fi
done < <(git ls-files '*lineage.dependencies')
if [ "$N_DEP" -eq 0 ]; then
    info "  （未找到 lineage.dependencies，跳过）"
elif [ "$BAD_DEP" -eq 0 ]; then
    ok "$N_DEP 份 JSON 合法"
fi

# ---- C5: 发布目录的 LICENSE -------------------------------------------------
info "[C5] 发布目录 LICENSE（Apache-2.0 §4(a)）"
N_LIC=0; BAD_LIC=0
for d in device-trees/los24-pandora; do
    [ -d "$d" ] || continue
    N_LIC=$((N_LIC + 1))
    if [ ! -f "$d/LICENSE" ]; then
        bad "$d 缺 LICENSE"; BAD_LIC=$((BAD_LIC + 1))
    elif [ "$(stat -c %s "$d/LICENSE" 2>/dev/null || echo 0)" -lt 10000 ]; then
        bad "$d/LICENSE 体积异常（疑为占位，应为 Apache-2.0 全文约 11 KB）"; BAD_LIC=$((BAD_LIC + 1))
    fi
    [ -d "$d" ] && [ ! -f "$d/NOTICE" ] && bad "$d 缺 NOTICE（上游出处声明）"
done
[ "$BAD_LIC" -eq 0 ] && ok "$N_LIC 个发布目录授权文件齐全"

# ---- C6: 脚本索引 -----------------------------------------------------------
hr
info "[C6] 脚本索引"
undoc=0
for f in $(git ls-files 'scripts/**' 'tools/**' | grep -E '\.(sh|py)$'); do
    # 排除自动生成的索引本身，否则这个指标是自我满足的
    n=$(grep -rl "$(basename "$f")" README.md docs/ 2>/dev/null | grep -v "docs/scripts-index.md" | wc -l)
    [ "$n" -eq 0 ] && undoc=$((undoc + 1))
done
info "  未被 README/手写文档引用的脚本：$undoc 个（仅提示，不计失败）"

if [ "$WRITE_INDEX" -eq 1 ]; then
    OUT=docs/scripts-index.md
    {
        echo "# 脚本索引"
        echo
        echo "> 由 \`scripts/maintain/selfcheck.sh --index\` 自动生成，请勿手改。"
        echo "> 说明取自文件头的首行注释。"
        echo
        for dir in scripts/build scripts/device scripts/dt scripts/flash scripts/maintain scripts/patch tools; do
            files=$(git ls-files "$dir/*" | grep -E '\.(sh|py)$' | sort)
            [ -z "$files" ] && continue
            echo "## $dir"
            echo
            echo "| 脚本 | 说明 |"
            echo "|---|---|"
            for f in $files; do
                desc=$("$PY" - "$f" <<'PY'
import io, re, sys
p = sys.argv[1]
lines = io.open(p, encoding="utf-8", errors="replace").read().splitlines()
d = ""
# 只读「文件头连续注释块」：shebang 之后、第一个非注释行之前。
# 不能全文件扫 # 行 —— 会把 heredoc 内嵌代码里的注释当成说明
# （实测 build_recovery_fb.sh 取到了 python 片段里的注释）。
for s in lines:
    s = s.strip()
    if s.startswith("#!"):
        continue
    if s.startswith("#"):
        t = s.lstrip("#").strip()
        if t and set(t) != {"="} and not t.startswith("-"):
            d = t
            break
        continue
    if s == "":
        continue
    if s.startswith('"""') and len(s) > 3:
        d = s.strip('"').strip()
    break
d = re.sub(r"\s+", " ", d)
print(d[:80] if d else "（无文件头说明）")
PY
)
                echo "| \`$(basename "$f")\` | $desc |"
            done
            echo
        done
    } > "$OUT"
    info "  已生成 $OUT（$(grep -c '^| `' "$OUT") 条）"
fi

# ---- 汇总 -------------------------------------------------------------------
hr
if [ "$FAIL" -eq 0 ]; then
    info "RESULT PASS"
    exit 0
fi
echo "RESULT FAIL（$FAIL 项）"
exit 1
