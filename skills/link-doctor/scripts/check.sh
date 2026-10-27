#!/usr/bin/env bash
# link-doctor 线上链接测活：抓取指定页面，提取同源链接逐个探测，输出 4xx/5xx 死链清单
# 用法:
#   bash check.sh <页面URL>                     # 单页体检（锚点去除；外链不探测仅可数）
#   bash check.sh <页面URL> --follow            # 单页体检 + 对发现的同源 .html 页各体检一层（限 20 页）
# 约束兼容：仅 http/https；只探测与入口同 host 的链接（github.io 公网域，无内网/环回风险）；
#           外链不主动请求。
set -uo pipefail

URL="${1:?用法: bash check.sh <页面URL> [--follow]}"
FOLLOW="${2:-}"
HOST=$(printf '%s' "$URL" | sed -E 's#^https?://([^/]+)/.*#\1#')
case "$URL" in
  http://*|https://*) ;;
  *) echo "仅支持 http/https 入口"; exit 1 ;;
esac

TMP=$(mktemp -d)
UA="Mozilla/5.0 (link-doctor/1.0)"

# 提取器：同源链接绝对化去重（脚本落盘再喂数据——python3 - 的 stdin 会被脚本本体占用）
cat > "$TMP/extract.py" << 'PYEOF'
import sys, re
from urllib.parse import urljoin, urlparse, quote
from html import unescape
base = sys.argv[1]
base_host = urlparse(base).netloc
html = sys.stdin.read()
seen = set()
for m in re.finditer(r'(?:href|src)="([^"#]+)"', html):
    raw = unescape(m.group(1))          # 属性实体（&amp; 等）还原——浏览器行为一致
    u = urljoin(base, raw)
    p = urlparse(u)
    if p.scheme not in ("http", "https"):
        continue
    if p.netloc != base_host:
        continue
    # 路径里的空格/全角字符按浏览器行为 percent-encode（否则 curl 直接 000 误报）
    enc = p.scheme + "://" + p.netloc + quote(p.path, safe="/:%@") \
        + ("?" + quote(p.query, safe="=&?/:") if p.query else "")
    if enc not in seen:
        seen.add(enc)
        print(enc)
PYEOF

fetch() {  # 大页（300KB+）跨境拉取可能慢：60s；疑似截断（<20KB）时重试一次
  local body
  body=$(curl -sL --max-time 60 -A "$UA" "$1")
  if [ ${#body} -lt 20000 ]; then
    sleep 2
    body=$(curl -sL --max-time 90 -A "$UA" "$1")
  fi
  printf '%s' "$body"
}

probe() {  # HEAD 优先，不支持时降级 GET；返回状态码
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -A "$UA" -I "$1" 2>/dev/null)
  case "$code" in
    000|403|405|501) code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -A "$UA" -L "$1" 2>/dev/null) ;;
  esac
  printf '%s' "$code"
}

check_page() {
  local page="$1" label="$2" total=0 dead=0
  fetch "$page" > "$TMP/page.html"
  python3 "$TMP/extract.py" "$page" < "$TMP/page.html" > "$TMP/links.txt"
  echo "== $label"
  echo "   页面: ${page}（$(wc -c < "$TMP/page.html" | tr -d ' ') 字节，$(wc -l < "$TMP/links.txt" | tr -d ' ') 条同源链接）"
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    total=$((total+1))
    code=$(probe "$link")
    case "$code" in
      2*) : ;;                       # 正常，不刷屏
      3*) echo "   ~ $code $link（重定向）" ;;
      *) echo "   ✗ $code $link"; dead=$((dead+1)); echo "$link" >> "$TMP/dead.txt" ;;
    esac
  done < "$TMP/links.txt"
  echo "   —— 探测 $total 条，死链 $dead 条"
}

rm -f "$TMP/dead.txt"
check_page "$URL" "单页体检"

if [ "$FOLLOW" = "--follow" ]; then
  grep '\.html$' "$TMP/links.txt" 2>/dev/null | head -20 | while IFS= read -r p; do
    check_page "$p" "follow: $(basename "$p")"
  done
fi

echo ""
if [ -s "$TMP/dead.txt" ]; then
  echo "== 死链清单（去重）"
  sort -u "$TMP/dead.txt" | sed 's/^/  /'
  rm -rf "$TMP"
  exit 1
else
  echo "全绿：无同源死链。"
  rm -rf "$TMP"
fi
