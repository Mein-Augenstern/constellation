"""经 api.github.com 的 git data API 在远端构造单提交（绕开 github.com 主站与整仓 fetch）。

用法: python3 api_commit.py <owner/repo> <branch> <commit_msg_file> <path,content_b64_json_file>
  path,content JSON: [{"path": "...", "content_b64": "..."}]
依赖: gh CLI 已认证（取 token）；纯标准库。
安全：出站仅连接固定常量主机 api.github.com（HTTPS，不跟随重定向），路径段由调用参数拼接。
"""
import base64
import http.client
import json
import subprocess
import sys

API_HOST = "api.github.com"  # 固定出站目标，不接受任意 URL
REPO, BRANCH, MSG_FILE, FILES_FILE = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
TOKEN = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True).stdout.strip()
BASE = f"/repos/{REPO}"
H = {"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json",
     "User-Agent": "constellation-api-commit", "Content-Type": "application/json"}


def call(method, path, body=None):
    conn = http.client.HTTPSConnection(API_HOST, timeout=60)
    try:
        payload = json.dumps(body).encode() if body is not None else None
        conn.request(method, BASE + path, body=payload, headers=H)
        resp = conn.getresponse()
        text = resp.read()
        if resp.status >= 300:
            raise RuntimeError(f"HTTP {resp.status}: {text[:200].decode('utf-8', 'replace')}")
        return json.loads(text) if text else {}
    finally:
        conn.close()


ref = call("GET", f"/git/ref/heads/{BRANCH}")
tip = ref["object"]["sha"]
base_tree = call("GET", f"/git/commits/{tip}")["tree"]["sha"]
print(f"remote {BRANCH} tip={tip[:10]} tree={base_tree[:10]}")

entries = []
for f in json.load(open(FILES_FILE)):
    blob = call("POST", "/git/blobs", {
        "content": base64.b64decode(f["content_b64"]).decode(), "encoding": "utf-8"})
    entries.append({"path": f["path"], "mode": "100644", "type": "blob", "sha": blob["sha"]})
tree = call("POST", "/git/trees", {"base_tree": base_tree, "tree": entries})["sha"]

commit = call("POST", "/git/commits", {
    "message": open(MSG_FILE).read().strip(), "tree": tree, "parents": [tip],
    "author": {"name": "muyi", "email": "34135120+Mein-Augenstern@users.noreply.github.com"},
})["sha"]
call("PATCH", f"/git/refs/heads/{BRANCH}", {"sha": commit, "force": False})
print(f"pushed commit {commit[:10]} onto {tip[:10]} ({len(entries)} files)")
