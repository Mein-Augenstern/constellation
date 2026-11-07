#!/usr/bin/env python3
"""转载文来源标注批量补齐（kb-article-writing 配套）。

规则（2026-11-07 用户决策产品化：转载文照常优化，条件是表明来源）：
  - 扫描 >6000 字、含博客域外链、无任何来源标注、非反哺系的文章；
  - 插入标准来源块（内容来源 + 原文链接×N + 版权 + 编辑加工说明）于首个小节前
    （fence 感知）；全角/半角引号形态不影响匹配（不匹配文本，只认域名清单）；
  - 反哺系（2026-XX 新增标记）自产文**不误标**——它们不是转载。

用法：python3 add-source-attribution.py [库根] [--dry-run]
已知边界（人工判断区）：外链属「参考阅读」性质而非原文的文章会被跳过——
  域名启发式无法区分「原文」与「参考」，残余交人工逐篇判断（2026-11-07 余 14 篇）。
"""
import os
import re
import sys
from pathlib import Path

TRACKS = ["A-后端内核", "B-AI工程", "C-架构", "D-云原生", "E-算法", "F-前端", "G-业务领域"]
SRC = re.compile(r"内容来源|整理自|转载自|原文地址|原文链接|原作者|文章来源|版权归原作者|来源清单")
REPAY = re.compile(r"2026-\d{2}\s*新增|生产实践反哺")
BLOG = re.compile(r"juejin|blog\.csdn|cnblogs|meituan|gitbook|zhihu|jianshu|infoq|segmentfault|github\.io", re.I)
EXT = re.compile(r"https?://[^\s\)\]\"]+", re.I)
MIN_CHARS = 6000

BLOCK = (
    "\n> **内容来源**：本篇为学习整理，转载自网络技术博客（版权归原作者所有）：\n"
    "{links}\n"
    "> 结构与表述有编辑加工；勘误与更新以原文为准。\n"
)


def insert_block(text: str, block: str) -> str:
    """插到首个小节标题之前（fence 感知）。"""
    lines = text.split("\n")
    insert_at = len(lines)
    fence = False
    for i, l in enumerate(lines):
        if re.match(r"^\s*```", l):
            fence = not fence
            continue
        if fence or i == 0:
            continue
        if re.match(r"^#{1,6}\s+", l) or (i + 1 < len(lines) and re.match(r"^-{2,}\s*$", lines[i + 1])):
            insert_at = i
            break
    lines.insert(insert_at, block)
    return "\n".join(lines)


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.getcwd())
    dry = "--dry-run" in sys.argv
    import os

    done = 0
    for t in TRACKS:
        d = root / t
        if not d.exists():
            continue
        for p in d.rglob("*.md"):
            if p.name.lower() == "readme.md":
                continue
            txt = p.read_text()
            chars = len(re.sub(r"\s", "", txt))
            if chars < MIN_CHARS or SRC.search(txt) or REPAY.search(txt):
                continue
            urls = [u.rstrip(".,;") for u in EXT.findall(txt) if BLOG.search(u)]
            seen = set()
            uniq = []
            for u in urls:
                if u not in seen:
                    seen.add(u)
                    uniq.append(u)
                if len(uniq) == 3:
                    break
            if not uniq:
                continue
            links = "\n".join(f"> - [原文链接]({u})" for u in uniq)
            block = BLOCK.format(links=links)
            if not dry:
                p.write_text(insert_block(txt, block))
            done += 1
            print(f"[补] {p}")
    print(f"{'[DRY] ' if dry else ''}补来源块 {done} 篇")


if __name__ == "__main__":
    main()
