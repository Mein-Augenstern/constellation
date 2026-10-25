---
name: github-cn
description: 国内断网环境下 GitHub 全流程操作套路。用户说"clone 仓库、推送、push 上去、gh 认证、加 SSH key、github 打不开、拉仓库"等且遭遇网络超时/阻断时触发。覆盖：api tarball 克隆、git data API 三步推送（不下载历史）、设备码授权、SSH-443 通道、镜像源速查。
---

# GitHub 断网环境操作套路（2026-10 实战验证）

背景：本机网络下 `github.com` 主站时断时续（整仓 fetch 大仓不可行），但 `api.github.com` / `codeload.github.com` 全程稳定。以下所有路径均绕开主站。

## 第一步：判断当前通道

```bash
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 8 https://github.com    # 主站窗口探测
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 8 https://api.github.com  # 应恒为 200
```

主站 200 = 窗口期，常规 git 操作抓紧做；超时 = 走下面的替代路径。

## 克隆：api tarball 快照法

```bash
GH_HOST=github.com gh api repos/<owner>/<repo>/tarball > /tmp/r.tar.gz
mkdir <repo> && tar -xzf /tmp/r.tar.gz -C <repo> --strip-components=1
cd <repo> && git init -q && git remote add origin git@github.com:<owner>/<repo>.git
git add -A && git commit -qm "snapshot of main @ $(date +%F)"
```

注意：这是**内容快照，无真实历史**。后续要对齐真实历史见"软重置对齐"。私有仓需 gh 已认证。

## 推送：git data API 三步提交（核心资产）

不走 git push，不下载历史，秒级完成快进提交。用本目录 `scripts/api_commit.py`：

```bash
python3 scripts/api_commit.py <owner>/<repo> <branch> <msg_file> <files_json>
# files_json: [{"path": "...", "content_b64": "..."}]（新增或整文件覆盖）
```

原理：GET ref → POST blobs/trees(base_tree) → POST commits(parents=远端tip) → PATCH ref。**绝不 force**，天然兼容分支保护。一次提交可带多文件。

已实战：MUYI 电子书功能、8 篇知识库文章（一篇一 commit）、constellation 全部推送。

## 本地历史对齐（快照仓 → 真实历史）

```bash
git fetch --depth=1 --filter=blob:none https://github.com/<owner>/<repo>.git <branch>
git reset --soft FETCH_HEAD && git read-tree HEAD   # read-tree 清掉局部克隆幻影差异
```

blob:none 只拉 commit+tree（KB 级）；缺的 blob 用 `git checkout HEAD -- <path>` 按需取。

## 授权与 SSH

* gh 认证：`gh auth login --hostname github.com --git-protocol https --web`（设备码，需主站窗口期）
* 补 scope（加 SSH key 需要 admin:public_key）：`gh auth refresh -h github.com -s admin:public_key`，token 交换也可能因主站超时失败，多试
* SSH 通道：`ssh.github.com:443` 恒通，`~/.ssh/config` 写 `Host github.com / HostName ssh.github.com / Port 443`；key 未挂账号前 SSH 不可用（Permission denied）

## 镜像源速查

npm→`registry.npmmirror.com`；PyPI→清华；Docker→daemon.json（`docker.m.daocloud.io` 等，Hub 直连多数加速源已死，pull-images.sh 多源轮询法备用）；JDK→清华 Adoptium（注意本机 macOS 无 PingFang 时测试字体换 Hiragino/STHeiti）。
