---
name: portfolio-sync
description: 个人多仓内容同步。当 Mein-Augenstern 下任一代码仓发生变化（新功能/新文章/测试数变化/新仓库/组件结构变化），精确识别所有需要联动更新的镜像面（个人主页站点、GitHub Profile README、各仓 README、知识库计数、时间线、代表作表）并逐处同步。用户说"同步个人主页、博客内容旧了、README 数据过期、推送后同步、全景数据同步、个人介绍更新、改了 XX 其他地方要不要改"等一律触发。同步前先跑 scripts/audit.sh 得到全镜像面差异清单。
---

# 个人多仓内容同步（portfolio-sync）

> 一处改动，多面镜像。本 skill 解决"代码仓变了，哪些对外内容跟着旧了"的问题：
> 精确到文件与区块级别的映射表 + 权威数据源 + 可执行核对脚本。
> 实战沉淀自 2026-10 的三次全量同步（组件库开源 / MUYI 343 篇 / CI 全绿）。

## 第 0 步：先跑差异审计

```bash
bash <skill目录>/scripts/audit.sh [GitHub工作区根目录，默认 ~/Documents/GitHub]
```

脚本会输出各镜像面关键数字的「显示值 vs 权威值」差异清单——把它作为本次同步的待办底稿，
再叠加下方映射表补齐脚本测不到的定性内容（新特性文案、链接、时间线事件）。

## 镜像面清单（8 面）

| # | 镜像面 | 本地路径 | 更新通道 |
|---|---|---|---|
| 1 | 个人主页站点 | `~/Documents/GitHub/mein-augenstern.github.io`（index.html + README.md） | git push master（Pages 自动部署） |
| 2 | GitHub Profile README | **无本地克隆**，`Mein-Augenstern/Mein-Augenstern` 仓 | `gh api -X PUT repos/Mein-Augenstern/Mein-Augenstern/contents/README.md`（需先 GET sha） |
| 3 | MUYI 知识库 README | `~/Documents/GitHub/MUYI/README.md` | git push master |
| 4 | 组件库 README | `~/Documents/GitHub/star-site-components/README.md` | git push main |
| 5 | backend README | `~/Documents/GitHub/star-site-backend/README.md` | git push main |
| 6 | invest 平台 README | `~/Documents/GitHub/invest/README.md` 或 invest-platform 子目录 | git push |
| 7 | constellation 星座 README | `~/Documents/GitHub/constellation/README.md`（+ skills/marketplace.json） | git push main |
| 8 | 电子书首页 | `~/Documents/GitHub/MUYI/book/index.md`（hero tagline 的篇数/题数——**构建进 Pages，本地改完即线上**） | 随 MUYI git push |
| 9 | docs/星图（低频） | `constellation/docs/星图-*.md` | 按需，季度级 |

## 权威数据源表（每个数字只有一个真源，禁止拍脑袋）

| 数字 | 权威来源 | 取法 |
|---|---|---|
| MUYI 篇数 | MUYI 仓最后一次文章 commit | `git log --oneline --grep="篇" -5` 里"第 N 篇"；比 find 数 md 可靠（find 会算入清单/台账文件） |
| 自测题数 | `MUYI/自测清单.md` | `grep -cE "^\| [0-9]+ \|" 自测清单.md` |
| 轨道细分（并发/JVM/Spring/数据库/信贷域/AI） | MUYI 各子目录 | `find <轨道目录> -name '*.md' \| wc -l`（排除 README） |
| 组件库测试数 | 组件仓构建输出 | `mvn clean verify` 末尾 `Tests run:` 汇总行；改完必须以重跑值为准 |
| 组件库模块/组件数 | 组件仓父 pom | `<module>` 计数 / 组件枚举 |
| backend 微服务数 | backend 目录 | `star-site-biz-*` + `star-site-platform-*`（不含 gateway？含）——按站点现行口径 11 服务 |
| 容器数 | `star-site-backend/docker/docker-compose.yml` | services 键计数 **减去一次性 init job**（`*-data` 等 `restart: "no"` 的一次性服务） |
| invest 测试数 | invest-platform | `.venv/bin/python -m pytest tests/ -q` 末尾汇总 |

## 改动类型 → 联动面映射表（核心）

| 触发改动 | 需同步的位置（精确到区块） |
|---|---|
| MUYI 新增文章 commit | ① 站点 hero 统计"深度笔记"+ whoami 块 find 数字 + MUYI 卡"篇数"（3 处）② Profile README 统计行"343 篇深度笔记" + MUYI 行 ③ MUYI README 徽章与体系节（文章 commit 通常自带，核对即可）④ **电子书首页 tagline**（book/index.md 的"N 篇实文/N 题自测"——曾漏同步停在 361/121） |
| MUYI 自测清单增删题 | ① 站点 MUYI 卡"自测清单 N 题" ② Profile README MUYI 行"N 题自测" ③ MUYI README 徽章（历史坑：徽章与正文曾不一致，三处必须同值） |
| 组件库测试数/模块数变化 | ① 组件仓 README"98 测试"等表述 ② 站点组件卡"98 项单测" + hero 第 4 格 ③ Profile README 组件行 |
| 组件库结构性变化（组件增减/模块合并） | 同上三面 + 站点 whoami `ls engineering/`（若出现新顶层目录）+ backend README 若引用了模块形态 |
| backend 功能落地（支付/锁/异步命令级别） | ① 站点 star-site 卡 bullet（技术亮点替换最旧一条，保持 3 条）② Profile README star-site-backend 行一句话 ③ 站点时间线 2025–26 条目追加 |
| 容器编排变化 | ① 站点 hero"18 容器" + star-site 卡"18 容器 Docker 编排" ② Profile README 统计行 |
| 新开源仓库 | ① 站点工程实践新增卡片（tag/标题/描述/3 bullet/公开链接）② Profile README 代表作表新增行（emoji+链接+一句话）③ 站点 README"相关仓库"④ Profile 统计"N+ 公开项目" |
| 新增生产反哺长文 | ① 站点"知识库精选"区视强弱替换末位 ② Profile README 深度文章列表追加 ③ MUYI README 生产反哺节 |
| constellation 新增 skill | ① `skills/marketplace.json` plugins 数组 ② constellation README 技能清单/描述行 ③（该 skill 产出重大时）站点时间线 |
| invest 功能/测试数变化 | ① 站点 invest 卡 bullet 与"99 项测试" ② Profile README invest 行 |
| 站点自身改版 | 站点 README"站点板块"节描述同步 |

## 工作流

1. **识别改动**：优先从当前会话上下文取（本会话改了什么你最清楚）；跨会话场景用
   `git -C <仓> log --oneline --since=<锚点>` 反推。锚点取上次同步 commit（各仓 git log 里
   找 "docs: 全景数据同步" 类提交）。
2. **跑 audit.sh** 拿到数字差异底稿，叠加映射表把定性改动（新特性/新链接/时间线事件）补成完整待办。
3. **逐面核实再改**：每个数字先按权威数据源表实测，再写入镜像面——出现过"本地实测 345 篇、
   仓库自声明 343 篇"的口径打架，**以仓库 commit 声明为准**（find 会算入非文章文件）。
4. **更新 Profile README**（无本地克隆）：先 `gh api repos/Mein-Augenstern/Mein-Augenstern/contents/README.md --jq '.sha'`
   拿 sha，PUT 时带上；内容经 base64 编码进 JSON body。
5. **全部推送后验证**：
   - CI 仓（components/backend/MUYI）`gh run list -R ... --limit 2` 确认 success；
   - 站点 WebFetch `https://mein-augenstern.github.io/?v=<时间戳>`（**必须带查询参数**——
     同 URL 有 15 分钟缓存 + Pages 部署延迟约 1 分钟）；
   - Profile README 换 `?ref=<sha>` 或直接 gh api 读回确认。

## 红线（每条都踩过）

- **脱敏不回写**：公开镜像面禁止出现雇主实名（已统一为"金融科技后端（信贷/交易方向）"）。
  从简历/私仓复制文案进公开面时先过一遍敏感词。
- **孤儿快照仓先对齐**：`mein-augenstern.github.io` 本地克隆可能是快照形态且落后线上——
  动手前必须 `git fetch origin master && git reset --hard origin/master`（先 `git status` 确认无未提交改动）。
  教训：曾差点用 5 个 commit 之前的旧版覆盖线上。
- **github SSH 首次操作可能挂起**：fetch/push 卡住先等 2 分钟再杀；profile README 走 gh api（https）可绕开。
- **数字三处一致**：篇数/题数/测试数在站点、Profile、仓库 README 三处出现，改一处必须 grep 另两处
  （`grep -rn "旧数字" <各镜像面路径>`）。
- **计数脚本与自声明冲突时信自声明**，并把差异记进本次 commit message（下次审计的锚点）。
