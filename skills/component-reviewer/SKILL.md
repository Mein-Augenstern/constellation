---
name: component-reviewer
description: 组件编码原则审视。用 SOLID 与组件库规约逐切面审查 star-site-components 三组件的实现代码，产出问题清单（类/违反原则/建议/优先级）并驱动优化。用户说"审视组件、巡检三组件、代码原则检查、职责单一吗、设计模式审视、组件代码优化"等一律触发。与 component-builder 的关系：builder 管建造规约（事前），本 skill 管实现审视（事后）——巡检发现的新原则回写进两个 skill。
---

# 组件编码原则审视（component-reviewer）

> 方法论：逐类切面审查，而非通读。每个类过六把尺子，发现即登记
> （类 / 违反原则 / 证据 / 建议 / 优先级），审完按优先级落地优化。
> 首轮实战（2026-10-30）产出两条新原则已回写 component-builder：
> 分布式状态存储端铁律、SQL 配置外置铁律。

## 六把尺子（按序过）

1. **单一职责（SRP）**：一句话说不清这个类"只做什么"就拆。警惕方法内混入
   其他职责的编排逻辑——判断法：把该方法移到协作者类是否更自然？
   （实战例：DbLockClient.tryLock 里的行丢失自愈编排属存储供给职责，移入 Provisioner）
2. **状态归属**：每个可变字段问"它的事实源在哪"——跨实例共享的事实必须在存储端
   （hold_count 列 / Redis hash field）；Pod 本地只允许性能提示缓存且必须带自愈路径。
3. **SQL/脚本配置外置**：Java 代码零 SQL 字符串（含动态过滤片段与 ORDER BY 片段）。
   MyBatis 消费走 Mapper XML；JDBC 方言走 `resources/sql/<组件>-mysql.xml`
   （`<statement id>`=方法名，CDATA 多行原生 SQL——**SQL 的直觉载体是 XML，properties 已否决**）；
   Redis Lua 走 `resources/sql/*.lua`。方言 Java 类只做安全加载（拒 DOCTYPE/外部实体）与 {table} 渲染。
4. **契约清晰**：接口 javadoc 说出语义边界与不保证什么（轮询非通知/无公平性/fail-open 粒度）；
   行为约束必须有对应测试锁死。
5. **DRY 与等价性**：三形态（jdbc/mybatis/memory）同一语义的重复实现，行为差异必须有
   测试互证（如列表不拉 payload 三形态同断言）。
6. **重复度检查**：超过两处相同的结构（脚本三态/双 RowMapper 列清单），评估收拢成本；
   刻意的重复（可读性）注释说明意图。
7. **注释规范**（2026-10-30 补——曾遗忘）：公开类/接口必带职责说明与 @author/@date；
   **每个公开方法（含 getter/setter）须有 javadoc**（孤例即缺陷——写"读取/设置 XX"即可，
   不许裸行）；SQL/Lua 配置逐条注释用途。巡检时专门扫最近提交的文件，注释缺失即登记。
   扫描脚本可参考：检查 `public` 行上方两行内是否有 `*/` 或 `//`，无即登记。

## 工作流

1. **圈范围**：用户点名的类优先（如 RedisLockClient/DbLockClient），未点名则扫
   `*/src/main/java` 全部核心类（跳过 model/config 纯数据类与 starter 粘合）。
2. **逐类过尺**：每类六尺顺序过，登记问题清单（markdown 表格，诚实记录包括"看起来该拆
   但拆了更糟"的否决判断——否决理由也是产出）。
3. **优先级排序**：正确性 > 职责 > 配置外置 > 可读性。正确性级问题当场修。
4. **落地优化**：按优先级改代码，每类问题一个 commit；改完全量 verify + backend 回归。
5. **原则回写**：本轮巡检发现的新原则，回写 component-builder（规约+检查表）与本 skill
   （新尺子或新实战例）——两个 skill 是同一套原则的事前/事后形态。

## 二轮巡检产出（2026-10-31，15 项修复回写）

| 新原则 | 来源 |
|---|---|
| **配置键迁移收尾检查**：改了 Properties 键名/枚举值后，必须 grep docs/*.md、README 双语版、starter javadoc、examples/*/application.yml 四处旧值残留——`store: memory` 为非法值会被 Spring 静默忽略（P1 实战） | 2026-10-31 二轮巡检 #1 |
| **三形态等价漏改防御**：给某一形态（如 JdbcStore）加功能后，必须 grep 同义其他形态（MyBatisStore/InMemoryStore）是否同步——8de4ac8 给 JdbcStore 注入 TimeSource 漏改了 MyBatis 形态 | 2026-10-31 二轮巡检 #4 |
| **Map.of 空安全**：Map.of() 不接受 null 值——REST 端点用 Map.of 返回结果时，可空参数须提前归一 | 2026-10-31 二轮巡检 #3 |
| **重取号静默默认 = 撞号风险**：分布式取号失败绝不可静默返回默认值（如 workerId=1），必须抛异常 | 2026-10-31 二轮巡检 #2 |
| **README 双语版同步检查**：改了英文版 README 的数字/JDK/命令后，grep 中文版对应位置是否同步 | 2026-10-31 二轮巡检 #6 |

## 首轮巡检结论存档（2026-10-30，三组件）

| 发现 | 尺子 | 处置 |
|---|---|---|
| SequenceSql.MySql / AsyncCommandSql.MySql：SQL 字符串在 Java 内 | 3 配置外置 | 外置方言 XML（初版误用 properties，当日按直觉载体原则纠正为 XML），类改安全加载器 |
| JdbcAsyncCommandStore：appendFilters/ORDER BY 片段 Java 拼接 | 3 配置外置 | 片段进同一 properties |
| RedisLockClient：Lua 脚本 Java 常量 | 3 配置外置（脚本=存储语句） | 外置 .lua 资源 |
| DbLockClient.tryLock：自愈编排混入互斥语义 | 1 SRP | 自愈移 Provisioner.healIfRowLost |
| 双 RowMapper 列重复 | 6 重复度 | 否决合并——显式两份各自注释，合并需反射/注解反而费解 |
| InMemory 与表形态分列等价 | 5 等价性 | 已有测试互证（本轮之前落地） |
