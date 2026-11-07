#!/usr/bin/env python3
"""全库七维体检（kb-article-writing 配套）：一次性产出治理决策所需的全部数据。

七维：①多H1 ②泛用首标题 ③巨无霸(>15k字) ④薄文(<500字) ⑤互链孤岛 ⑥≥7篇无导读目录 ⑦死链
用法：python3 global-audit.py [库根] [--json 输出路径]
     库根默认 cwd；自动发现轨道（根下含 *.md 的顶层目录），排除 book/.git/images/node_modules。
     只读不写——治理动作交给其他三个脚本。
2026-11-07 定稿：三形态标题识别（setext1/setext2/ATX）、标题扫描不 break（11/4 行级
扫描器 break 于首个非标题块，漏掉 35 篇"标题前有引言文"的形态——本版已修）。
"""
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import unquote

EXCLUDE_DIRS = {"book", "node_modules", "images", ".git", "docs", "dist", "src"}
GENERIC = {"看在前面", "文章清单", "Question", "前言"}
GIANT_CHARS = 15000
HOLLOW_CHARS = 500


def headings(text):
    """全文档标题序列 [(level, text)]：三形态识别 + 代码围栏感知。"""
    lines = text.split("\n")
    fence = False
    out = []
    for i, l in enumerate(lines):
        if re.match(r"^\s*```", l):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r"^(#{1,6})\s+(.+)$", l)
        if m:
            out.append((len(m.group(1)), m.group(2).strip()))
            continue
        if i + 1 < len(lines) and l.strip():
            if re.match(r"^=+\s*$", lines[i + 1]):
                out.append((1, l.strip()))
            elif re.match(r"^-{2,}\s*$", lines[i + 1]):
                out.append((2, l.strip()))
    return out


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.getcwd())
    json_out = None
    if "--json" in sys.argv:
        json_out = sys.argv[sys.argv.index("--json") + 1]
    tracks = [d for d in sorted(root.iterdir())
              if d.is_dir() and d.name not in EXCLUDE_DIRS
              and any(d.rglob("*.md"))]

    all_md = [p for t in tracks for p in t.rglob("*.md")]
    inbound = Counter()
    for p in all_md:
        for m in re.finditer(r"\]\(([^)#\s]+\.md)\)", p.read_text()):
            inbound[os.path.basename(unquote(m.group(1)))] += 1

    multi_h1, generic_first, giant, hollow, no_inbound = [], [], [], [], []
    dircount = Counter()
    for p in all_md:
        txt = p.read_text()
        hs = headings(txt)
        chars = len(re.sub(r"\s", "", txt))
        if hs and hs[0][1] in GENERIC:
            generic_first.append(str(p))
        if sum(1 for lv, _ in hs[1:] if lv == 1) > 0:
            multi_h1.append(str(p))
        if chars > GIANT_CHARS:
            giant.append([chars, str(p)])
        if chars < HOLLOW_CHARS:
            hollow.append([chars, str(p)])
        if p.name.lower() != "readme.md" and inbound.get(p.name, 0) == 0:
            no_inbound.append(str(p))
        dircount[p.parent] += -1 if p.name.lower() == "readme.md" else 1

    no_readme_dirs = sorted([str(d) for d, c in dircount.items() if c >= 7 and not (d / "README.md").exists()],
                            key=lambda s: -dircount[Path(s)])
    dead = []
    for t in tracks + ([root / "自测清单.md"] if (root / "自测清单.md").exists() else []):
        files = [t] if t.is_file() else list(t.rglob("*.md"))
        for p in files:
            for m in re.finditer(r"\]\(([^)#h][^)#?]*)\)", p.read_text()):
                raw = unquote(m.group(1))
                if not raw.startswith("."):
                    continue
                if not (p.parent / raw).resolve().exists():
                    dead.append(f"{p} -> {m.group(1)}")

    print(f"库根: {root} | 轨道: {len(tracks)} | md 总数: {len(all_md)}")
    print(f"① 多H1        : {len(multi_h1)}")
    print(f"② 泛用首标题  : {len(generic_first)}")
    print(f"③ 巨无霸>{GIANT_CHARS}字 : {len(giant)}")
    for c, p in sorted(giant, reverse=True)[:6]:
        print(f"     {c:6d} {p}")
    print(f"④ 薄文<{HOLLOW_CHARS}字 : {len(hollow)}")
    print(f"⑤ 互链孤岛    : {len(no_inbound)}")
    print(f"⑥ ≥7篇无导读  : {len(no_readme_dirs)}")
    for d in no_readme_dirs[:10]:
        print(f"     {dircount[Path(d)]:3d} 篇  {d}")
    print(f"⑦ 死链        : {len(dead)}")
    for d in dead[:10]:
        print(f"     {d}")

    if json_out:
        Path(json_out).write_text(json.dumps({
            "multi_h1": multi_h1, "generic_first": generic_first,
            "giant": giant, "hollow": hollow, "no_inbound": no_inbound,
            "no_readme_dirs": no_readme_dirs, "dead": dead,
        }, ensure_ascii=False, indent=1))
        print(f"JSON → {json_out}")


if __name__ == "__main__":
    main()
