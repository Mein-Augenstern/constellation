# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mcp>=1.2.0,<2",  # 2.x 把 FastMCP 改名为 MCPServer（mcp.server.mcpserver），迁移后再升
#   "httpx>=0.27",
# ]
# ///
"""star-site MCP server：把家庭健康后端（网关 /api）暴露为 MCP 工具。

运行：uv run server.py          （uv 自动解决 Python>=3.10 与依赖）
环境变量：
  STAR_SITE_BASE_URL  网关地址，默认 http://127.0.0.1:8080/api（本地 compose 网关；
                      9090 是 frp 公网入口，公网访问时才用）
  STAR_SITE_TOKEN     登录 JWT；未配置时可先调 login 工具换取
"""
from __future__ import annotations

import os
from datetime import date
from typing import Any, Optional

import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("star-site")

BASE_URL = os.environ.get("STAR_SITE_BASE_URL", "http://127.0.0.1:8080/api")
TOKEN = os.environ.get("STAR_SITE_TOKEN", "")


def _client() -> httpx.Client:
    headers = {"Authorization": f"Bearer {TOKEN}"} if TOKEN else {}
    return httpx.Client(base_url=BASE_URL, headers=headers, timeout=15.0)


def _unwrap(path: str, resp: httpx.Response) -> Any:
    resp.raise_for_status()
    body = resp.json()
    if body.get("code") != 0:
        raise RuntimeError(f"{path} -> code={body.get('code')}, message={body.get('message')}")
    return body.get("data")


def _get(path: str, params: Optional[dict] = None) -> Any:
    with _client() as c:
        return _unwrap(path, c.get(path, params=params))


def _post(path: str, json_body: dict) -> Any:
    with _client() as c:
        return _unwrap(path, c.post(path, json=json_body))


@mcp.tool()
def login(username: str, password: str) -> dict:
    """账号密码登录，换取 JWT 并在本会话内自动用于后续工具调用。
    拿到 token 后建议写入 ZCode 的 mcpServers env 配置，免每次登录。"""
    global TOKEN
    data = _post("/auth/login", {"username": username, "password": password})
    TOKEN = data.get("token", TOKEN)
    member = data.get("member") or {}
    return {"logInAs": member.get("nickname") or member.get("username"), "tokenSaved": True}


@mcp.tool()
def my_profile() -> dict:
    """当前登录用户资料（/member/me）。"""
    return _get("/member/me")


@mcp.tool()
def list_family_members() -> list:
    """全家成员档案：id、姓名、关系（self/spouse/child/father/mother）、出生日期。
    后续查报告/记指标都要用这里的 familyMemberId。"""
    return _get("/family/members")


@mcp.tool()
def list_reports(
    page: int = 1,
    size: int = 10,
    family_member_id: Optional[int] = None,
    year: Optional[int] = None,
) -> dict:
    """分页查询全家体检报告。family_member_id 限定某位成员，year 限定年份。
    返回 {records, total, page, size}。"""
    params: dict = {"page": page, "size": size}
    if family_member_id is not None:
        params["familyMemberId"] = family_member_id
    if year is not None:
        params["year"] = year
    return _get("/health/reports", params)


@mcp.tool()
def upcoming_reminders(days: int = 7) -> list:
    """未来 N 天内的提醒待办（复查/用药/疫苗等），按到期日排序。"""
    return _get("/reminder/upcoming", {"days": days})


@mcp.tool()
def add_metric(
    family_member_id: int,
    metric_type: str,
    value_num: float,
    metric_date: Optional[str] = None,
) -> list:
    """记一条健康指标打卡。metric_type 取值：weight / bp_sys / bp_dia / glucose / heart_rate。
    metric_date 格式 YYYY-MM-DD，缺省今天。血压一次量两值请分别调 bp_sys 和 bp_dia 两次。"""
    item = {
        "familyMemberId": family_member_id,
        "metricType": metric_type,
        "valueNum": value_num,
        "metricDate": metric_date or date.today().isoformat(),
    }
    return _post("/health/metrics", {"items": [item]})


@mcp.tool()
def metric_trend(family_member_id: int, metric_type: str) -> list:
    """查询某成员某类指标的每日趋势序列（metricDate + valueNum），用于看变化。"""
    return _get("/health/metrics/trends", {"familyMemberId": family_member_id, "metricType": metric_type})


if __name__ == "__main__":
    mcp.run()
