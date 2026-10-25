---
name: wxdevtools-vision
description: 微信开发者工具在本机无辅助功能权限（Computer Use 不可用/osascript 受限）时的截图驱动排障与项目修复。用户说"开发者工具报错、小程序打不开、模拟器白屏、app.json 未找到、截图看看开发者工具"等场景触发。覆盖：截图+sips 裁剪放大+视觉模型逐字读、WeappLog 日志定位、miniprogramRoot 修复、项目记录存储位置。
---

# 微信开发者工具视觉排障（无辅助功能权限路线）

前提：Computer Use 在部分会话不可用、System Events 需要"辅助功能"授权（未授权时 osascript 报 -25211）。本套路全程只用：`screencapture` / `sips` / 视觉模型（analyze_image）/ 日志文件，不需要任何 UI 自动化权限。

## 排障五步

1. **截图看现场**：`open -a wechatwebdevtools` 后 `sleep 10` 再截（Electron 冷启动慢，第一次截可能只有桌面壁纸）：

```bash
open -a wechatwebdevtools && sleep 10 && screencapture -x /tmp/wx.png
sips -g pixelWidth /tmp/wx.png                      # retina 全屏很大
sips -c <高> <宽> --cropOffset <y> <x> /tmp/wx.png --out /tmp/crop.png   # 裁关键区
```

2. **视觉模型逐字读**：把截图交给视觉模型，prompt 要求"逐字读出错误/日志/按钮文字"——比人眼截屏靠谱，注意结果可能截断，关键区域要裁剪放大后再读一轮。
3. **日志定位真因**（比截图更准）：`~/Library/Application Support/微信开发者工具/<hash>/WeappLog/logs/`，取最新 `.log` grep 关键词。经典错误样例：

```
[BackendInitEnv] getAppJSON error app.json: 在项目根目录未找到 app.json
[appservice] simulator launch failed ...
```

4. **修 miniprogramRoot**（uni-app 项目最高频）：源码根目录没有 app.json 导致"项目根目录未找到"——在源码根 `project.config.json` 加 `"miniprogramRoot": "dist/dev/mp-weixin/"`，并保证 `pnpm dev:mp-weixin` 处于 watch（产物目录存在）。
5. **验证闭环**：重启工具 → 再截屏确认模拟器渲染 → 日志 grep `app.json` 计数为 0。

## 已知坐标

* 进程名是 `Electron`（不是 wechatwebdevtools），System Events 枚举用它
* 项目列表/最近项目记录：`~/Library/Application Support/微信开发者工具/<hash>/WeappLocalData/localstorage_*.json`（`reduxPersist:projectList` 键，hash_key_map_2.json 反查文件名）；改存储前先退出工具再备份
* CLI（`cli open --project`）需要"服务端口"开启：设置→安全设置→服务端口，默认关闭
* 本机 CJK 字体缺失会连累测试/截图造图：PingFang 不存在时用 Hiragino Sans GB / STHeiti

## 实战案例

2026-10-21 invest-miniapp 打开报错：日志实锤 `app.json 未找到`（克隆仓无 node_modules/dist 且未配 miniprogramRoot）→ pnpm 装依赖 + 后台跑 dev watch + 配 miniprogramRoot → 重启工具，日志零报错、模拟器出页面。
