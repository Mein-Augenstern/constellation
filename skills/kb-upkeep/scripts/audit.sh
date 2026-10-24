#!/bin/bash
# kb-upkeep 体检脚本：空壳/链接占位/外链图测活(抽样)/相对死链/文字外链测活/结构统计
# 用法: audit.sh [库路径] [-f 全量图片测活] [-l 全量文字外链测活]
set -u
KB="${1:-/Users/yangzhini/Documents/GitHub/MUYI}"
FULLIMG=""; FULLLINK=""
for a in "$@"; do case "$a" in -f) FULLIMG="-f";; -l) FULLLINK="-l";; esac; done
cd "$KB" || { echo "库不存在: $KB"; exit 1; }

echo "===== 知识库体检: $KB ====="
echo

echo "--- [1] 空壳文档（0字节 或 有效行<8，排除 picture/readme/链接集合页占位）---"
n1=0
while IFS= read -r f; do
  case "$f" in *picture*|*readme*|*README*|*推荐阅读*|*瞎看系列*|*大模型学习材料*|*front_Q_address*) continue;; esac
  size=$(wc -c < "$f" | tr -d ' ')
  [ "$size" -eq 0 ] && { echo "  0字节: $f"; n1=$((n1+1)); continue; }
  lines=$(grep -vcE '^\s*$' "$f" | head -1)
  [ "${lines:-99}" -lt 8 ] && { echo "  ${lines}行: $f"; n1=$((n1+1)); }
done < <(find . -name "*.md" -not -path "./.git*" -not -path "./.mimosa*" -not -path "./book*" -not -path "*/node_modules*")
echo "  小计: $n1"
echo

echo "--- [2] 链接占位（有效行<=8 且含链接，排除已知集合页）---"
n2=0
while IFS= read -r f; do
  case "$f" in *推荐阅读*|*瞎看系列*|*大模型学习材料*|*front_Q_address*) continue;; esac
  total=$(grep -vcE '^\s*$' "$f" | head -1)
  links=$(grep -cE 'https?://' "$f")
  if [ "${total:-99}" -le 8 ] && [ "${links:-0}" -ge 1 ]; then echo "  行:$total 链:$links | $f"; n2=$((n2+1)); fi
done < <(find . -name "*.md" -not -path "./.git*" -not -path "./.mimosa*" -not -path "./book*" -not -path "*/node_modules*")
echo "  小计: $n2"
echo

echo "--- [3] 外链图片测活（默认抽样10张；-f 全量）---"
urls_file=$(mktemp)
grep -rhoE '!\[[^]]*\]\(https?://[^)]+\)' --include='*.md' . 2>/dev/null | sed 's/^.*(\(.*\))$/\1/' | sort -u > "$urls_file"
total=$(wc -l < "$urls_file" | tr -d ' ')
if [ "$FULLIMG" = "-f" ]; then sample_file="$urls_file"; else sample_file=$(mktemp); head -10 "$urls_file" > "$sample_file"; fi
ok=0; dead=0; err=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  code=$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 8 "$u" 2>/dev/null)
  case "$code" in
    200|301|302) ok=$((ok+1));;
    404|410) dead=$((dead+1)); echo "  DEAD $u";;
    *) err=$((err+1));;
  esac
done < "$sample_file"
echo "  唯一外链图: ${total}；本轮测 $(wc -l < "$sample_file" | tr -d ' ')：ok=$ok dead=$dead unknown=$err"
rm -f "$urls_file" "$sample_file"
echo

echo "--- [4] 库内相对死链 ---"
n4=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in \#*|mailto:*) continue;; esac
    decoded=$(python3 -c "from urllib.parse import unquote; print(unquote('''$link'''))" 2>/dev/null)
    # 以 / 开头的是仓库根相对路径（GitHub md 约定），其余相对 md 所在目录
    case "$decoded" in
      /*) target=".$decoded";;
      *) target="$dir/$decoded";;
    esac
    [ -e "$target" ] || { echo "  死链: $f -> $link"; n4=$((n4+1)); }
  done < <(grep -hoE '\]\(([^)h#][^)]*)\)' "$f" 2>/dev/null | sed 's/^](\(.*\))$/\1/' | sed 's/#.*$//')
done < <(find . -name "*.md" -not -path "./.git*" -not -path "./.mimosa*" -not -path "./book*" -not -path "*/node_modules*")
echo "  小计: $n4"
echo

echo "--- [5] 文字外链测活（默认抽样20条；-l 全量；先剥离图片链避免与[3]重复）---"
# 仅 http/https；请求前校验 host，拒绝 localhost/环回/私有/保留地址
links_file=$(mktemp)
find . -name "*.md" -not -path "./.git*" -not -path "./.mimosa*" -not -path "./book*" -not -path "*/node_modules*" -print0 2>/dev/null \
  | xargs -0 cat 2>/dev/null \
  | sed 's/!\[[^]]*\]([^)]*)//g' \
  | grep -oE '\]\(https?://[^)[:space:]]+\)' \
  | sed 's/^](\(.*\))$/\1/' | sort -u > "$links_file"
l_total=$(wc -l < "$links_file" | tr -d ' ')
if [ "$FULLLINK" = "-l" ]; then sample_l="$links_file"; else sample_l=$(mktemp); head -20 "$links_file" > "$sample_l"; fi
n5_ok=0; n5_dead=0; n5_err=0; n5_warn=0; n5_skip=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  host=$(printf '%s' "$u" | sed -E 's#https?://([^/]+).*#\1#')
  case "$host" in
    localhost*|127.*|0.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|*.local|*\[*)
      echo "  SKIP(内网/非法host): $u"; n5_skip=$((n5_skip+1)); continue;;
  esac
  code=$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 8 "$u" 2>/dev/null)
  case "$code" in
    200|201|204|226|301|302|304) n5_ok=$((n5_ok+1));;
    000) n5_err=$((n5_err+1));;
    404|410) echo "  DEAD($code) $u"; n5_dead=$((n5_dead+1));;
    *) echo "  HTTP$code(人工复核) $u"; n5_warn=$((n5_warn+1));;
  esac
done < "$sample_l"
echo "  唯一文字外链: ${l_total}；本轮测 $(wc -l < "$sample_l" | tr -d ' ')：ok=$n5_ok dead=$n5_dead warn=$n5_warn unknown=$n5_err skip=$n5_skip"
rm -f "$links_file" "$sample_l"
echo

echo "--- [6] 结构统计 ---"
total_md=$(find . -name "*.md" -not -path "./.git*" -not -path "./.mimosa*" -not -path "./book*" -not -path "*/node_modules*" | wc -l | tr -d ' ')
echo "  md 总数: $total_md"
readme_claim=$(grep -oE '[0-9]+\+? 篇深度笔记' README.md 2>/dev/null | head -1 | grep -oE '^[0-9]+')
[ -n "$readme_claim" ] && { [ "$readme_claim" -ge "$total_md" ] && echo "  README 声称 $readme_claim 篇（<=实际 ✓）" || echo "  ⚠ README 声称 $readme_claim 但实际 $total_md"; }
for d in A-后端内核 B-AI工程 C-架构 D-云原生 E-算法 F-前端 G-业务领域; do
  [ -d "$d" ] && echo "  $d: $(find "$d" -name '*.md' | wc -l | tr -d ' ') 篇"
done

echo
echo "===== 体检完成：空壳 $n1 / 占位 $n2 / 相对死链 $n4 / 外链死图本轮 $dead / 文字外链死链本轮 $n5_dead(warn $n5_warn) ====="
