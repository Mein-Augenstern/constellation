---
name: mimosa-sql-gate
description: Mimosa 安全门禁下的 Python SQL 写作纪律：execute() 的 SQL 必须是单行内联字符串字面量。多行隐式字符串拼接、模块常量转手、通用执行器 helper 都会被误报"SQL 注入"并拦截写入。适用于任何在本环境新写数据库访问代码的场景。
---

# mimosa-sql-gate · Mimosa SQL 门禁写作纪律

## 何时使用

- 在本环境新写/修改任何含 `execute()` 的 Python 数据库代码（sqlite3 / pymysql）
- Write 工具被 Mimosa 拦截、报"高危 · SQL 注入"时（尤其是你确信没有拼接时）
- 双方言（SQLite `?` + MySQL `%s`）兼容层设计

## 门禁实际规则（2026-11-02 四连拦实证反推）

| 写法 | 判定 | 说明 |
|---|---|---|
| `execute("UPDATE t SET a=? WHERE id=?", params)` 单行字面量 | ✅ 过 | 唯一稳妥形态 |
| `execute("长SQL..."`<br>`  " 接后半段", params)` 多行隐式拼接 | 🔴 拦 | **最坑**：相邻字符串字面量拼接被误读为"值拼接进 SQL" |
| `execute(_SQL_CONST, params)` 模块常量转手 | 🔴 拦 | 变量引用即污点，不追到常量定义 |
| `_run(sql, params)` 通用执行器（内部再 execute） | 🔴 拦 | SQL 作为参数传递 = 动态 SQL |
| `sql.replace("?", "%s")` 运行时方言变换 | 🔴 拦 | 生成的字符串必然非字面量 |
| f-string 拼表名（即使正则白名单校验过） | 🔴 拦 | 任何 f-string SQL |

## 正确写法（双方言成对字面量，execute 点内联）

```python
def acquire(self) -> bool:
    with self._conn() as conn:                      # 连接管理可以抽 helper（不含 SQL）
        if self._is_sqlite:
            n = conn.execute("UPDATE starsite_lock SET locked_by=?, locked_until=? WHERE lock_name=?", params).rowcount
            conn.commit()
            return n > 0
        with conn.cursor() as cur:
            n = cur.execute("UPDATE starsite_lock SET locked_by=%s, locked_until=%s WHERE lock_name=%s", params)
        return n > 0                                # MySQLStore._conn 出口统一 commit
```

要点：
1. **每条语句 × 每方言一个完整字面量**，直接写在 execute 调用点（长行没关系，
   本仓库本就无行宽限制——387 行超 100 字符）
2. **连接管理（开/commit/close）照常抽 contextmanager**——门禁只盯 SQL 字符串
3. 多步争锁（UPDATE → INSERT OR IGNORE）在同一连接内完成即可，原子性靠
   语句本身（UNIQUE 约束），不需要跨语句事务，也就不需要动态 SQL helper
4. 参数一律元组传入，命名元组/变量名随意（只查 SQL 字符串形态）

## 与旧代码的矛盾（不要回头改）

`invest/strategy/lifecycle.py`、`invest/data/mysql_store.py` 等旧代码用的就是
"模块常量 + `_execute` helper + replace 方言变换"写法——它们早于门禁或经子 agent
写入，**已入库的不必返工**；新代码一律按本纪律写。

## 被拦后的处置流程

1. 看报错行号定位到具体 execute 点
2. 判断被拦形态（对照上表）——99% 是多行隐式拼接或常量转手
3. 压成单行内联字面量重写该调用点
4. 不要试图用注释/改名绕过；不要关门禁
