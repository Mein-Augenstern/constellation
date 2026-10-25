# constellation · 个人 AI 能力星座

> My personal constellation of AI skills & MCP servers — every skill a star, managed from the Observatory.

工作与生活的 AI 协作能力总仓：**skill（技能）+ MCP server（工具）** 统一沉淀在此，
后续扩展管理后台 **Observatory**（观测星座的天文台——skill/mcp 的注册、启停、版本与健康检查）。

## 仓库结构

```
constellation/
├── skills/                          # 星：ZCode 技能（每个技能一个目录 + SKILL.md）
│   ├── marketplace.json             # 技能市场清单
│   ├── brainstorm-archive/          # 演绎/竞品/决策 → docs 编号文档体系
│   ├── kb-upkeep/                   # 知识库体检-修复-增补闭环（MUYI 等 md 库）
│   └── star-site-miniprogram-automation/  # 小程序 E2E 自动化套路
├── mcp/                             # 星：MCP server（每个 server 独立可运行）
│   └── star-site/                   # 家庭健康后端（网关 /api）的 MCP 出口
├── docs/                            # 星图：工具使用真相与速查（docs/星图-2026-10.md）
└── apps/                            # （规划）Observatory 管理后台
```

## 使用技能（skills）

在 ZCode 中添加本地市场并安装：

```
# 市场指向本仓库 skills/ 目录（marketplace.json 所在处）
# 之后可安装 brainstorm-archive / kb-upkeep / star-site-miniprogram-automation
```

技能规范：每技能一个目录 + `SKILL.md`（frontmatter：`name` + `description`），
脚本放 `scripts/`，插件元数据放 `.zcode-plugin/plugin.json`。

## 使用 MCP server

以 star-site 为例（uv 运行，自动解决 Python>=3.10 与依赖）：

```bash
# 1. 配置环境（可选，默认连本地 compose 网关）
cp mcp/star-site/.env.example mcp/star-site/.env   # .env 已 gitignore

# 2. 在 ZCode（或其它 MCP 客户端）注册：
#    command: uv
#    args:    [run, <本仓库绝对路径>/mcp/star-site/server.py]
#    env:     STAR_SITE_BASE_URL=http://127.0.0.1:8080/api  STAR_SITE_TOKEN=<JWT，可先不填用 login 工具换>
```

环境变量说明见 `mcp/star-site/.env.example`：`STAR_SITE_BASE_URL`（默认本地网关 8080，
公网走 frp 入口 9090）、`STAR_SITE_TOKEN`（登录 JWT，未配置时先调 login 工具换取）。

## 约定

- 新增技能：`skills/<name>/SKILL.md` + 登记 `skills/marketplace.json`
- 新增 MCP：`mcp/<name>/` 自带依赖声明（PEP 723 script meta 或 package.json），独立可运行
- 秘密文件（`.env`）不入库；工具状态目录（`.mimosa/`）不入库
- 迁移来源：本仓库由 guo-skills + guo-mcp（2026-10 换机前的本地仓）合并而来

## License

私人仓库，暂不开源协议；公开镜像部分另行声明。
