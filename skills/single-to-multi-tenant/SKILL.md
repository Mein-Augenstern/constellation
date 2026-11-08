---
name: single-to-multi-tenant
description: 单用户系统改造为多会员（多租户）数据隔离的工程清单。store 层 member 维度设计、None 回落兼容、整行匹配删除换自增 id、幂等迁移与对账、双 JWT 越权测试、SQLite 并发锁坑、泄露密钥轮换决策。
---

# single-to-multi-tenant · 单用户 → 多会员数据隔离改造清单

## 何时使用

- 单用户系统（个人工具）要开放注册/多账号，用户数据必须互相不可见
- 老数据（CSV/无 owner 维度的表）需要平滑归属到某个初始会员
- 不想大爆炸重写：要求既有 CLI/定时任务/全部旧测试**零改动**继续通过

## 设计核心：兼容式隔离（None 回落）

所有用户数据方法加 `member_id: int | None = None` 参数，**None = 默认会员**
（env 配置，生产指向运营者）：

```python
def list_diary(self, member_id: int | None = None, ...):
    mid = member_id if member_id is not None else default_member_id()
```

- Web 路由：从鉴权层拿真实 member_id 显式传入（隔离生效）
- CLI/调度器/旧测试：不传 → 默认会员 → 行为与单用户时代**完全一致**
- 公共数据（行情序列/指数目录）不加维度，全会员共享缓存

### member_id 从哪来

鉴权中间件解析 JWT 的 `sub` → `request.state.member_id` → FastAPI 依赖
`get_member_id()`（无登录态时回落默认值）。角色用 env 名单表达
（`ADMIN_MEMBER_IDS=31`），守卫依赖 `require_admin` → 403。

## 改造清单（按序执行）

### 1. store 层（双后端逐方法对齐）

- 新表带 member_id（如 `trades(id 自增, member_id, ...)`）
- 旧表加列：`ALTER ADD member_id NULL` → `UPDATE SET member_id=<默认> WHERE NULL` → 以后写入必带
- **唯一键/主键升级**：`UNIQUE(date)` → `UNIQUE(member_id, date)`；
  `PRIMARY KEY(id)` → `PRIMARY KEY(member_id, id)`（SQLite 改约束须重建小表拷数，
  记得 `IFNULL(col,'')` 防 NULL 撞 NOT NULL）
- 迁移放 store 初始化里，**幂等**（探列存在才动），进程内按库文件缓存只跑一次

### 2. 删除口径：自增 id 替代整行匹配

整行匹配删除（CSV 时代无奈之举）有两类历史 409：数值格式容差、空值 vs 0 归一。
迁库顺手换 `DELETE ... WHERE member_id=? AND id=?`（越权 id 天然等价不存在），
保留整行匹配函数一个迭代期兼容旧客户端，然后下线。

### 3. 路由层

- 读路径：`trades=Depends(get_trades)`（store 化）替换 `load_trades(csv_path)`
- 写路径：store 追加 + **审计**（who/what/when/traceId，不含金额明文）
- 产物类数据（周报文件）按 `reports/<member_id>/` 归档
- 备份导出**重写为会员自身数据**——旧"整目录导出"在多会员下是跨会员泄密面

### 4. 迁移与对账（一次脚本，幂等可重跑）

```
旧数据 → 备份 → store 追加 → 对账（行数 + 现金流/汇总值双向一致）
幂等判定：库内与旧数据逐行一致 → 跳过；库内有数据但不一致 → 拒绝（防重复追加）
```

### 5. 越权测试（双 JWT 模式）

自铸两个会员的 JWT（A=admin，B=member），断言：

| 动作 | 期望 |
|---|---|
| B 列流水/总览/日记/标的 | 不含 A 的任何数据 |
| B 按 A 的 id 删除 | 409/404（越权=不存在） |
| B 访问 admin 端点 | 403 |
| A/B 同日各写日记 | 互不覆盖（复合唯一键生效） |
| 旧客户端整行删除 | 仍 200（兼容期） |
| 审计 | 写操作留痕且**无金额明文** |

### 6. 坑两枚（实证）

- **SQLite WAL 只在初始化设一次**：逐连接 `PRAGMA journal_mode=WAL` 需要独占锁，
  与后台线程（周报/定时任务）并发必现 `database is locked`。修法：WAL 持久化在库文件里，
  逐连接只设 `busy_timeout` + `connect(timeout=10)`
- **每请求构造 store 的系统**：迁移语句若每次 init 都跑，会和后台线程锁竞争——
  进程内按库文件缓存"已迁移"标记

## 泄露密钥轮换决策（常伴随出现）

- git 历史里有密钥：**轮换使其失效 > 重写历史**（filter-repo 代价大且协作方需同步）
- 多服务共享 secret（如 JWT 密钥）：生成新值 → **同批更新所有持有方**（各仓 env/
  服务器 secrets）→ 逐个重启 → 用旧凭据验证 401、新凭据验证 200 收口
- 只能由平台侧轮换的（如微信 AppSecret）：登记待办催办用户，代码侧先出库止血

## 实证记录

- 2026-11-08 invest S11-P2：179 既有测试零改动 + 9 项越权回归全绿（188）；
  生产双账号验收（运营者见 7788 资产/新会员全空/越权 409/admin 403）；
  MySQL 实迁 2 行现金流 -5500 双向对账一致（bf7e749）
