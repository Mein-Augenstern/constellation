#!/usr/bin/env bash
# portfolio-sync 差异审计：跨镜像面提取关键数字，与权威源比对，输出差异清单
# 用法: bash audit.sh [GitHub工作区根目录]   # 默认 ~/Documents/GitHub
# 设计：只读不写；缺仓/缺工具跳过并标注，绝不失败退出
set -uo pipefail

ROOT="${1:-$HOME/Documents/GitHub}"
PAGES="$ROOT/mein-augenstern.github.io"
MUYI="$ROOT/MUYI"
COMP="$ROOT/star-site-components"
BACKEND="$ROOT/star-site-backend"
PROFILE_TMP="$(mktemp -t profile-readme)"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

# ---------- 镜像面加载 ----------
[ -f "$PAGES/index.html" ] && HAVE_PAGES=1 || { HAVE_PAGES=0; red "缺站点仓: $PAGES"; }
[ -d "$MUYI" ] && HAVE_MUYI=1 || { HAVE_MUYI=0; red "缺 MUYI: $MUYI"; }
[ -d "$COMP" ] && HAVE_COMP=1 || { HAVE_COMP=0; red "缺组件仓: $COMP"; }
[ -d "$BACKEND" ] && HAVE_BACKEND=1 || { HAVE_BACKEND=0; red "缺 backend: $BACKEND"; }

# Profile README 无本地克隆，gh api 拉线上（https，绕开 SSH 挂起问题）
if command -v gh >/dev/null 2>&1; then
  gh api 'repos/Mein-Augenstern/Mein-Augenstern/contents/README.md' --jq '.content' 2>/dev/null \
    | base64 -d > "$PROFILE_TMP" 2>/dev/null
fi
PROFILE_N=$(wc -l < "$PROFILE_TMP" | tr -d ' ')
if [ "$PROFILE_N" -gt 5 ]; then HAVE_PROFILE=1; else HAVE_PROFILE=0; red "Profile README 未取到（gh 不可用或未登录）"; fi

# ---------- 比对工具 ----------
declare -a SEEN_VALUES
report_metric() {  # $1=指标名 $2=权威值 $3..=面=值 对
  local name="$1" canon="$2"; shift 2
  echo ""
  echo "== $name  权威值: ${canon:-<未知>}"
  local v bad=0
  SEEN_VALUES=()
  for pair in "$@"; do
    v="${pair#*=}"
    if [ -z "$v" ]; then continue; fi
    if [ -n "$canon" ] && [ "$v" != "$canon" ] && [ "$v" != "$canon+" ]; then
      red "  ✗ ${pair%%=*} = $v"
      bad=1
    else
      green "  ✓ ${pair%%=*} = $v"
    fi
  done
  [ "$bad" = 0 ] || true
}

# ---------- ① MUYI 篇数 ----------
CANON_ARTICLES=""
if [ "$HAVE_MUYI" = 1 ]; then
  # 权威源：最后一次文章 commit 声明的总数。取"，N 篇"逗号总数式优先——
  # 轨道级"第 N 篇"（如"C-架构第 61 篇"）是子计数，不能当全库总数
  CANON_ARTICLES=$(git -C "$MUYI" log --oneline -30 2>/dev/null \
    | grep -oE "[，,][0-9]{2,4} 篇" | head -1 | grep -oE "[0-9]+")
  [ -z "$CANON_ARTICLES" ] && CANON_ARTICLES=$(git -C "$MUYI" log --oneline -30 2>/dev/null \
    | grep -oE "[0-9]{3} 篇" | head -1 | grep -oE "[0-9]+")
fi
p_hero=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '<dt>[0-9]+</dt><dd>深度笔记' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
p_term=$( [ "$HAVE_PAGES" = 1 ] && grep -B0 -A2 'find MUYI' "$PAGES/index.html" | grep -oE '>[0-9]+<' | head -1 | tr -d '><' )
p_card=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '[0-9]{3} 篇源码级笔记' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
m_readme=$( [ "$HAVE_MUYI" = 1 ] && grep -oE '[0-9]{3} 篇(实文|源码级|深度)' "$MUYI/README.md" | grep -oE '[0-9]+' | head -1 )
pr_stat=$( [ "$HAVE_PROFILE" = 1 ] && grep -oE '\`[0-9]{3} 篇深度笔记\`' "$PROFILE_TMP" | grep -oE '[0-9]+' | head -1 )
report_metric "MUYI 篇数" "$CANON_ARTICLES" \
  "站点hero=${p_hero:-}" "站点终端块=${p_term:-}" "站点MUYI卡=${p_card:-}" "MUYI-README=${m_readme:-}" "Profile=${pr_stat:-}"

# ---------- ② 自测题数 ----------
CANON_QUIZ=""
[ "$HAVE_MUYI" = 1 ] && [ -f "$MUYI/自测清单.md" ] \
  && CANON_QUIZ=$(grep -cE '^\| [0-9]+ \|' "$MUYI/自测清单.md")
p_quiz=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '自测清单：[0-9]+ 题' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
m_badge=$( [ "$HAVE_MUYI" = 1 ] && grep -oE '\`[0-9]+ 题自测闭环\`' "$MUYI/README.md" | grep -oE '[0-9]+' | head -1 )
m_body=$( [ "$HAVE_MUYI" = 1 ] && grep -oE '[0-9]+ 题 × 答案定位' "$MUYI/README.md" | grep -oE '[0-9]+' | head -1 )
pr_quiz=$( [ "$HAVE_PROFILE" = 1 ] && grep -oE '[0-9]+ 题自测' "$PROFILE_TMP" | grep -oE '[0-9]+' | head -1 )
report_metric "自测题数" "$CANON_QUIZ" \
  "站点MUYI卡=${p_quiz:-}" "MUYI-README徽章=${m_badge:-}" "MUYI-README正文=${m_body:-}" "Profile=${pr_quiz:-}"

# ---------- ③ 组件库测试数（权威=组件仓README声明；改代码后须 mvn verify 重核） ----------
CANON_TESTS=""
[ "$HAVE_COMP" = 1 ] && CANON_TESTS=$(grep -oE '[0-9]+ (项单测|测试全绿|个测试)' "$COMP/README.md" | grep -oE '[0-9]+' | head -1)
p_comp=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '[0-9]+ 项单测' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
p_hero4=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '开源组件 · [0-9]+ 测试' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
pr_comp=$( [ "$HAVE_PROFILE" = 1 ] && grep -oE '[0-9]+ 测试 \+ 真库 IT' "$PROFILE_TMP" | grep -oE '[0-9]+' | head -1 )
report_metric "组件库测试数(权威=组件README声明)" "$CANON_TESTS" \
  "站点组件卡=${p_comp:-}" "站点hero=${p_hero4:-}" "Profile=${pr_comp:-}"

# ---------- ④ 容器数 ----------
# 只数 services: 段下的键——volumes: 段同为两空格缩进，混数会虚高（mysql-data/file-data 是卷不是容器）
CANON_CONT=""
if [ "$HAVE_BACKEND" = 1 ] && [ -f "$BACKEND/docker/docker-compose.yml" ]; then
  CANON_CONT=$(awk '/^services:/{f=1;next} /^[A-Za-z]/{f=0} f && /^  [A-Za-z0-9_-]+:$/{c++} END{print c}' \
    "$BACKEND/docker/docker-compose.yml")
fi
p_cont=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '<dt>[0-9]+</dt><dd>容器微服务' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
p_cardc=$( [ "$HAVE_PAGES" = 1 ] && grep -oE '[0-9]+ 容器 Docker 编排' "$PAGES/index.html" | grep -oE '[0-9]+' | head -1 )
pr_cont=$( [ "$HAVE_PROFILE" = 1 ] && grep -oE '[0-9]+ 容器编排' "$PROFILE_TMP" | grep -oE '[0-9]+' | head -1 )
report_metric "容器数(compose服务-一次性job)" "$CANON_CONT" \
  "站点hero=${p_cont:-}" "站点star-site卡=${p_cardc:-}" "Profile=${pr_cont:-}"

# ---------- ⑤ 公开仓库清单 vs Profile/站点登记面 ----------
echo ""
echo "== 公开仓登记核对（GitHub 全部公开仓 vs Profile/站点提及）"
COVERED=$( { [ "$HAVE_PROFILE" = 1 ] && grep -oE 'github.com/Mein-Augenstern/[a-zA-Z0-9-]+' "$PROFILE_TMP"; \
              [ "$HAVE_PAGES" = 1 ] && grep -oE 'github.com/Mein-Augenstern/[a-zA-Z0-9-]+' "$PAGES/index.html" "$PAGES/README.md"; } \
            | grep -oE '[a-zA-Z0-9-]+$' | sort -u )
if command -v gh >/dev/null 2>&1; then
  PUBLIC=$(gh api 'users/Mein-Augenstern/repos?per_page=100' --paginate --jq '.[] | select(.fork == false and .name != "Mein-Augenstern") | .name' 2>/dev/null | sort -u)
  for repo in $PUBLIC; do
    case "$repo" in
      # pages 仓经站点 URL 登记（Profile 作品集/站点自链），不走仓库地址形态，非缺口
      mein-augenstern.github.io) continue ;;
    esac
    if grep -qx "$repo" <<<"$COVERED"; then
      green "  ✓ $repo"
    else
      red "  ✗ $repo 公开但未在 Profile/站点登记（新开源仓需补：站点卡片+Profile代表作+相关仓库）"
    fi
  done
else
  dim "  gh 不可用，跳过公开仓核对；Profile 侧已登记：$(echo "$COVERED" | tr '\n' ' ')"
fi

echo ""
dim "审计完成——✗ 行即本次同步待办。定性内容（新特性文案/链接/时间线）映射见 SKILL.md 映射表。"
rm -f "$PROFILE_TMP"
