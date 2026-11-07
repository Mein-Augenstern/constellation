#!/usr/bin/env python3
"""标题治理（kb-article-writing 配套）：多H1 降级 + 泛用首标题修复——三形态识别定稿版。

两个能力（java/redis 全库治理三轮实证，修掉过两版 fixer 的三个 bug）：
  ① 多H1 降级：首标题（三形态任一）保留，其余 h1 一律降 h2
     —— 书站 outline 只收 h2/h3，小节写 h1 会让右侧导航空白
  ② 泛用首标题修复：首标题是泛用小节名（看在前面/文章清单/Question/前言）时，
     真标题（文件名）插顶、泛用名降 h2——侧栏与页 H1 取首个标题，泛用名会割裂导航

用法：python3 fix-headings.py [库根] [--dry-run]
定稿要点（每个 bug 都踩过）：
  - 标题扫描**不 break**（11/4 版在首个非标题块 break，漏 35 篇"标题前有引言文"）；
  - 首标题判定识别**三形态**（11/6 版只认 ====，把「看在前面(----)+小节(====)」
    的小节误当首标题保留——残留 12 篇）；
  - 泛用名匹配注意全角弯引号（"Question？"类），不匹配文本只认固定词表。
"""
import re
import sys
from pathlib import Path

GENERIC = {"看在前面", "文章清单", "Question", "前言", "前言：", "引言"}
TRACKS = ["A-后端内核", "B-AI工程", "C-架构", "D-云原生", "E-算法", "F-前端", "G-业务领域"]


def headings(text):
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
            out.append((len(m.group(1)), m.group(2).strip(), i, "atx"))
            continue
        if i + 1 < len(lines) and l.strip():
            if re.match(r"^=+\s*$", lines[i + 1]):
                out.append((1, l.strip(), i, "se1"))
            elif re.match(r"^-{2,}\s*$", lines[i + 1]):
                out.append((2, l.strip(), i, "se2"))
    return out


def fix_file(p: Path, dry: bool) -> str:
    text = p.read_text()
    hs = headings(text)
    if not hs:
        return "no-heading"
    lines = text.split("\n")
    action = "none"

    # ① 泛用首标题：真标题插顶 + 泛用名降 h2
    if hs[0][1] in GENERIC:
        title = p.stem
        _, _, idx, style = hs[0]
        if style == "se1":
            lines[idx + 1] = re.sub(r"=", "-", lines[idx + 1])
        elif style == "atx":
            lines[idx] = "## " + hs[0][1]
        # se2 已经是 h2，无需改下划线
        lines.insert(0, "")
        lines.insert(0, "=" * max(4, min(len(title), 60)))
        lines.insert(0, title)
        action = "generic-fixed"

    # ② 多H1 降级（重新扫描——①可能改变了结构）
    hs = headings("\n".join(lines))
    seen_first = False
    i = 0
    fence = False
    while i < len(lines):
        l = lines[i]
        if re.match(r"^\s*```", l):
            fence = not fence
            i += 1
            continue
        if fence or not l.strip():
            i += 1
            continue
        m = re.match(r"^(#{1,6})\s+", l)
        if m:
            if not seen_first:
                seen_first = True
            elif len(m.group(1)) == 1:
                lines[i] = "#" + l
                action = action if action != "none" else "multi-h1"
            i += 1
            continue
        if i + 1 < len(lines) and lines[i + 1].strip():
            nxt = lines[i + 1]
            if re.match(r"^=+\s*$", nxt):
                if not seen_first:
                    seen_first = True
                else:
                    lines[i + 1] = re.sub(r"=", "-", nxt)
                    action = action if action != "none" else "multi-h1"
                i += 2
                continue
            if re.match(r"^-{2,}\s*$", nxt):
                seen_first = True
                i += 2
                continue
        i += 1

    if action != "none" and not dry:
        p.write_text("\n".join(lines))
    return action


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.getcwd())
    dry = "--dry-run" in sys.argv
    import os

    counts = {}
    for t in TRACKS:
        d = root / t
        if not d.exists():
            continue
        for p in d.rglob("*.md"):
            if p.name.lower() == "readme.md":
                continue
            act = fix_file(p, dry)
            if act not in ("none", "no-heading"):
                counts[str(p)] = act
    print(f"{'[DRY] ' if dry else ''}修复 {len(counts)} 篇")
    for k, v in list(counts.items())[:10]:
        print(f"  [{v}] {k}")


if __name__ == "__main__":
    main()
