---
name: frontend-build-inject-verify
description: 前端构建期配置注入（API 基址等）的可靠写法与运行时验证纪律。覆盖 vite import.meta.env 不内联、define 的 typeof 逃逸、多入口 chunk 误判、rawPath 类分支漏拼——以及"产物含值≠运行时用上"的 fetch 拦截验证法。
---

# frontend-build-inject-verify · 构建期注入与运行时验证纪律

## 何时使用

- 前端需要把构建期值（API 基址/环境标记）打进产物，尤其**同一代码库要出同源/跨域两种部署**
- 线上出现「请求 404/405 打到静态站」「配置像没生效」类症状
- 想在 CI 里守住这类回归

## 核心原则

**产物里有这个字符串 ≠ 运行时真的用上了。** 验收必须看运行时真实请求 URL，
不看 grep 结果。（2026-11-08 invest 登录 405 排障：产物 grep 命中隧道地址 ×1，
运行时却在请求相对路径 `/api/auth/login` 打到 pages.dev 静态站 → 405。）

## 四个坑（按踩的顺序，全部实证）

### 1. `import.meta.env.X` 的可选链/断言写法不被内联

```ts
// ❌ 产物里保留动态访问，构建期 env 未注入时运行时为 undefined
const base = (import.meta.env.VITE_API_BASE as string | undefined)?.replace(...) ?? ''
```
→ 需要构建期确定的值，走 `define`：

```ts
// vite.config.ts
define: { __API_BASE__: JSON.stringify(env.VITE_API_BASE || process.env.VITE_API_BASE || '') }
// client.ts
declare const __API_BASE__: string
const API_BASE = __API_BASE__.replace(/\/$/, '')
```

### 2. define 的 `typeof` 守卫会逃逸替换

```ts
// ❌ typeof __API_BASE__ 不被替换 → 运行时对未声明全局取 typeof → 恒 'undefined' → 走空分支
const base = typeof __API_BASE__ !== 'undefined' ? __API_BASE__ : ''
// 死分支里的字面量仍在产物中——grep 会命中，造成"已注入"假象！
```
→ define 键**直接裸用**，不写任何守卫。

### 3. 一次构建多个 `index-*.js`：grep 要先认准真入口

vite 可能产出主 entry（几十 KB）+ 同名前缀碎 chunk（百来字节）。
`ls -t | head -1` 和 glob 都可能抓错。甄别法：
- `grep -o 'index-*.js' dist/index.html` —— html 引用的才是入口
- 上下文比对：`grep -oE '.{40}关键字.{20}'` 看**赋值形态**（`ke="https://..."`）而非仅命中

### 4. rawPath/特殊分支漏拼基址（逻辑坑，构建工具无关）

```ts
// ❌ 只给业务前缀拼了 base，网关裸路径分支漏掉——同源部署时恰好正确，跨域部署必炸
let full = rawPath ? url : `${API_BASE}${BASE_PATH}${url}`
// ✅
let full = rawPath ? `${API_BASE}${url}` : `${API_BASE}${BASE_PATH}${url}`
```
教训：**每个 URL 出口都要过基址函数**，新加分支时先写该函数的单测
（`buildUrl` 的两条分支都应有 vitest 断言）。

## 运行时验证法（排障标准动作，10 分钟定位）

浏览器控制台/自动化里劫持 fetch，看**应用自己**发的真实 URL：

```js
window.__reqs = [];
const orig = fetch;
window.fetch = (input, init) => {
  const url = typeof input === 'string' ? input : input?.url;
  return orig.apply(this, arguments).then(res => {
    window.__reqs.push({ url, method: init?.method || 'GET', status: res.status });
    return res;
  });
};
// 触发一次业务动作后读 window.__reqs
```

- URL 是相对路径 → 基址没进运行时（坑 1/2/4）
- URL 正确但 `TypeError: Failed to fetch` → CORS 层问题（查响应头重复/缺失）
- 状态可读（如 405）→ 请求到达了但打错服务器（如静态站 POST → 405 Method Not Allowed 是 Pages/nginx 静态服务的签名）

## CI 守门（防回归）

对"同一代码库多部署形态"的项目：

```yaml
- name: 注入冒烟
  run: printf 'VITE_API_BASE=https://example-tunnel.example\n' > .env.production.local \
    && <build> && rm .env.production.local
- name: 断言替换形态
  run: grep -oE '[a-zA-Z_$]+="https://example-tunnel[^"]+"' dist/assets/$(grep -o 'index-[^"]*\.js' dist/index.html)   # 必须命中赋值形态
```

## 实证记录

- 2026-11-08 invest pages.dev 登录 405：三坑叠加（可选链 → typeof 守卫 → rawPath 漏拼），
  用 fetch 拦截法 10 分钟收敛到真因；修复后 25 项前端测试 + buildUrl 双分支回归全绿（ea27560）
