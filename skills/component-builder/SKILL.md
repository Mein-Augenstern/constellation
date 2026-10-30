---
name: component-builder
description: star-site 系列通用组件构造十步规约。用户说"建组件、新建组件、组件改造、组件标准化"时触发。沉淀自 star-site-components 三组件（sequence/async-command/lock）实战，后续所有组件建设一律按此执行。
---

# 组件构造十步规约（star-site-components 实战沉淀）

> 铁律先记三条：**表无 AUTO_INCREMENT，物理主键一律 sequence 发号**；
> **SQL 一律 Mapper XML，Java 零硬编码 SQL**；**每表必有 id / gmt_create / gmt_modified**。

## 第 1 步：模块骨架（core/starter 双模块）

- `starsite-<name>`（core）：零 Spring Boot 依赖，可脱离 starter 独立使用
- `starsite-<name>-spring-boot-starter`：仅粘合（自动装配 + 生命周期托管），本体全在 core
- **不再单设 mybatis 适配模块**（实战教训：适配模块代码量小且无独立使用场景）——
  MyBatis 路径直接进 core：Mapper 接口 + 同包 XML 放 `com.xp.starsite.<name>.mybatis` 包，
  mybatis/mybatis-spring 依赖 `provided`（由消费方 classpath 提供，不传递强制）；
  MyBatis 专用自动装配放 starter（`@ConditionalOnBean(SqlSessionFactory)` + 
  `@AutoConfigureAfter(MybatisAutoConfiguration by name)` + `@AutoConfigureBefore(默认装配)`）
- starter 内注册 `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`
  （MyBatis 装配排在默认装配之前）

## 第 2 步：分包（package-per-concern）

`model / config / clock / facade / client / executor / scheduler / store / metrics / admin`
——每个包一个职责，评审时按包扫。门面（facade）+ 客户端（client）是消费方唯一入口。

## 第 3 步：胖模型拆分（状态机收编枚举）

模型类不塞行为；状态流转逻辑收进枚举状态机（如 `CommandStatus.canAutoTransitionTo / isTerminal / fromCode`），
非法流转在模型层就抛，不漏到 store。

## 第 4 步：表设计（组件表标准三字段）

```sql
CREATE TABLE IF NOT EXISTS xxx (
    id           BIGINT      NOT NULL PRIMARY KEY,   -- sequence 组件发号，禁 AUTO_INCREMENT
    ...          业务列,
    gmt_create   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
)
```

- id 生成器经 `java.util.function.LongSupplier` 注入（core 不依赖 sequence 模块，解耦）；
  starter/适配层从容器取 `StarsiteIdGenerator`，**缺失即快速失败**（IllegalStateException + 提示引 starter），不许静默降级
- insert 前先 `cmd.setId(idGenerator.getAsLong())` 再落库——**禁用 GeneratedKeyHolder 回填**（那是 AUTO_INCREMENT 的配套）
- 测试里 idGenerator 用 `AtomicLong::incrementAndGet`；固定值 `() -> 1` 会跨用例主键冲突，且 fail-open 会掩盖冲突

## 第 5 步：SQL 载体（Mapper XML，同包自动发现）

- Mapper 接口**纯接口零注解 SQL**；XML 放 `src/main/resources` 下与接口**同包路径**，
  `Configuration.addMapper(XxxMapper.class)` 按命名空间自动发现加载
- 约定：`${tableName}` 为白名单校验（`[A-Za-z0-9_]+`）后的表名替换；业务值一律 `#{}` 参数绑定
- 接口多参数时实体参数必须 `@Param("cmd")`，XML 写 `#{cmd.xxx}`（ParamMap 无属性直通）
- **SQL 配置外置铁律（2026-10-30 巡检产出）**：MyBatis 消费走 Mapper XML；JDBC 方言语句放
  `resources/sql/mysql/<组件>-mysql.properties`（key=方言接口方法名，Java 类只做加载与缺键快速失败）；
  Redis Lua 放 `resources/sql/*.lua`。动态过滤/分页排序片段也是方言方法（filterStatus/pageOrderLimit），
  **Java 里连 AND 片段都不拼**。配套健全性测试：断言配置 key 与接口全对齐（缺键提前到 CI 暴露）

## 第 6 步：事务与并发

- **分布式状态铁律：跨实例共享的状态必须存存储端，禁止 Pod 本地变量承载正确性**。
  实战例：锁重入计数曾放实例内存 Map（同 ownerId 两 Pod 各数各的，B 一次 unlock 放掉 A 的外层锁）——
  改为锁表 `hold_count` 列（UPDATE 内 CASE 递增/递减）/Redis hash（field=ownerId，value=层数，Lua 原子）
  后跨实例共享一致。Pod 本地只允许**性能提示缓存**（如播种记忆），且必须配自愈路径
  （未抢到时校验存活性→作废缓存→重试），正确性不得依赖它
- 编程式事务：`TransactionTemplate` 回调（方法名避开 `execute`——安全门禁误报），**不用 @Transactional**（库不感染宿主代理配置）
- 多实例互斥：两步令牌法（UPDATE 认领 + 按令牌取回，派生表绕 MySQL ERROR 1093）；
  单条原子认领走 UPDATE 条件命中即 `>0`

## 第 7 步：调度与线程

- 执行模式枚举穷尽（SCHEDULED/ASYNC_POOL/IMMEDIATE），每类型线程池隔离（PoolIsolatedExecutor）
- 分布式调度三模式：COMPETING（默认抢跑）/ LEADER（lock 组件选主）/ EXTERNAL（外部触发 /tick）
- start/stop 经 SmartLifecycle 托管（phase = MAX：最后启动、最先停止）

## 第 8 步：配置拆分

core 的 `XxxConfig`（业务参数）+ starter 的 `XxxProperties extends XxxConfig`（追加 enabled/store 形态项）。
缺关键依赖（DataSource/IdGenerator/Redis）快速失败并提示替代配置，不留 NPE。

## 第 9 步：starter 让位清单（@ConditionalOnMissingBean 全覆盖）

Store / Client / Scheduler / Mapper / Metrics / HealthIndicator / AdminGuard——
应用自定义任何一个 Bean，自动装配整体让位；micrometer/actuator 缺席时 NOOP 降级不阻断。

## 第 10 步：测试与构建门禁

- 单测 H2 内存库全链路（建表 → 提交 → 认领 → 执行 → 回收 → 分页）；真库 IT 前缀 `*IT.java` 走 failsafe，
  `-Pit` 显式开启（默认 skipITs）
- **H2 踩坑清单**（全部实战验证过）：`MERGE INTO ... KEY` 是替换整行（种子行会覆盖他方持锁状态，
  改 `INSERT ... SELECT ... WHERE NOT EXISTS`）；`MERGE WHEN MATCHED AND` 条件不成立也计影响行数
  （互斥判定失真，改纯 UPDATE）；不支持 `INSERT IGNORE`/`INTERVAL ? SECOND`/`NOW(3)`
  （改参数绑定阈值时刻、`#{now}` 绑定）
- Spotless（Apache-2.0 头 + import 排序）validate 期门禁；父 pom 管 BOM 与插件版本

## 12 项快速检查表（交付前过一遍）

1. 表三字段齐（id/gmt_create/gmt_modified）且无 AUTO_INCREMENT？
2. id 来源是 sequence（LongSupplier 注入），starter 缺 generator 快速失败？
3. SQL 全在 Mapper XML（或方言接口），Java 零 SQL 字符串？
4. XML 与接口同包、命名空间一致、实体参数 `@Param` 前缀对齐？
5. `${}` 仅白名单表名，业务值全 `#{}` 参数绑定？
6. 多实例并发语义有测试（令牌互斥/续期/释放）；跨实例状态在存储端（Pod 本地仅性能提示缓存且带自愈）？
7. 编程式事务，无 @Transactional？
8. 线程池隔离 + SmartLifecycle 托管？
9. 让位清单全覆盖（ConditionalOnMissingBean）？
10. H2 踩坑清单的 5 个坑没再犯？
11. Spotless + 全模块 verify 绿？
12. README 有引 jar + 配置即用的最小示例？
