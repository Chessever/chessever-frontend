#!/usr/bin/env python3
"""Pull and summarize recent Sentry crash/error issues.

Required:
  SENTRY_AUTH_TOKEN with event:read access.

Optional:
  SENTRY_ORG          Sentry organization slug.
  SENTRY_PROJECT      Sentry project slug.
  SENTRY_PROJECT_ID   Numeric project id. If omitted, parsed from .env DSN.
  SENTRY_BASE_URL     Defaults to https://sentry.io. Use https://de.sentry.io
                      for EU-region orgs if sentry.io returns auth/not found.
  SENTRY_STATS_PERIOD Defaults to 72h.

Output:
  tmp/sentry_crashes_72h.json
  tmp/sentry_crashes_72h.md
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TMP_DIR = ROOT / "tmp"
DEFAULT_STATS_PERIOD = "72h"


def getenv(name: str) -> str | None:
    value = os.environ.get(name)
    return value.strip() if value and value.strip() else None


def read_env_value(name: str, path: Path = ROOT / ".env") -> str | None:
    if not path.exists():
        return None
    pattern = re.compile(rf"^\s*{re.escape(name)}\s*=\s*(.*)\s*$")
    for line in path.read_text(errors="ignore").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        value = match.group(1).strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        return value or None
    return None


def dsn_project_id() -> str | None:
    dsn = getenv("SENTRY_DSN") or getenv("SENTRY_FLUTTER") or read_env_value("SENTRY_FLUTTER")
    if not dsn:
        return None
    try:
        parsed = urllib.parse.urlparse(dsn)
    except ValueError:
        return None
    parts = [part for part in parsed.path.split("/") if part]
    return parts[-1] if parts else None


def api_url(base_url: str, path: str, params: dict[str, Any] | None = None) -> str:
    url = f"{base_url.rstrip('/')}{path}"
    if params:
        query = urllib.parse.urlencode(params, doseq=True)
        url = f"{url}?{query}"
    return url


class SentryApi:
    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token

    def get(
        self,
        path: str,
        params: dict[str, Any] | None = None,
        *,
        tolerate_404: bool = False,
    ) -> tuple[Any, str | None]:
        request = urllib.request.Request(
            api_url(self.base_url, path, params),
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/json",
                "User-Agent": "chessever-sentry-crash-audit/1.0",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read().decode("utf-8")
                return json.loads(body), response.headers.get("Link")
        except urllib.error.HTTPError as exc:
            if tolerate_404 and exc.code == 404:
                return None, None
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"Sentry API GET {path} failed with HTTP {exc.code}: {detail[:800]}"
            ) from exc

    def get_pages(
        self,
        path: str,
        params: dict[str, Any],
        *,
        max_pages: int,
    ) -> list[Any]:
        items: list[Any] = []
        cursor: str | None = None
        for _ in range(max_pages):
            page_params = dict(params)
            if cursor:
                page_params["cursor"] = cursor
            page, link = self.get(path, page_params)
            if not isinstance(page, list):
                raise RuntimeError(f"Expected list from {path}, got {type(page).__name__}")
            items.extend(page)
            cursor = next_cursor(link)
            if not cursor:
                break
        return items


def next_cursor(link_header: str | None) -> str | None:
    if not link_header:
        return None
    for part in link_header.split(","):
        if 'rel="next"' not in part or 'results="true"' not in part:
            continue
        match = re.search(r"[?&]cursor=([^>&]+)", part)
        if match:
            return urllib.parse.unquote(match.group(1))
    return None


def discover_org(api: SentryApi) -> str:
    orgs, _ = api.get("/api/0/organizations/")
    if not isinstance(orgs, list) or not orgs:
        raise RuntimeError("No organizations returned for SENTRY_AUTH_TOKEN.")
    if len(orgs) == 1:
        return str(orgs[0]["slug"])
    slugs = ", ".join(str(org.get("slug")) for org in orgs)
    raise RuntimeError(f"Multiple Sentry orgs found. Set SENTRY_ORG explicitly. Found: {slugs}")


def tag_map(event: dict[str, Any] | None) -> dict[str, str]:
    tags: dict[str, str] = {}
    if not event:
        return tags
    for item in event.get("tags") or []:
        key = item.get("key")
        value = item.get("value")
        if key is not None and value is not None:
            tags[str(key)] = str(value)
    return tags


def exception_text(event: dict[str, Any] | None) -> str:
    if not event:
        return ""
    chunks: list[str] = []
    for entry in event.get("entries") or []:
        if entry.get("type") != "exception":
            continue
        values = ((entry.get("data") or {}).get("values")) or []
        for value in values:
            chunks.append(str(value.get("type") or ""))
            chunks.append(str(value.get("value") or ""))
            frames = (((value.get("stacktrace") or {}).get("frames")) or [])[-12:]
            for frame in frames:
                chunks.append(str(frame.get("module") or ""))
                chunks.append(str(frame.get("function") or ""))
                chunks.append(str(frame.get("filename") or ""))
    return "\n".join(part for part in chunks if part)


def classify(issue: dict[str, Any], event: dict[str, Any] | None) -> list[str]:
    haystack = "\n".join(
        [
            str(issue.get("title") or ""),
            str(issue.get("culprit") or ""),
            json.dumps(issue.get("metadata") or {}, sort_keys=True),
            exception_text(event),
        ]
    )
    rules = [
        ("notification-channel-startup", ["NotificationChannel", "ChessEverApplication", "createNotificationChannels"]),
        ("live-notification", ["NotificationServiceExtension", "live_notification", "postLocalLiveNotification"]),
        ("pip", ["PictureInPicture", "ChessPiP", "enterPictureInPicture", "setPictureInPictureParams"]),
        ("native-audio", ["SoundPool", "flutter_soloud", "SoLoud", "ChessSfx"]),
        ("stockfish", ["Stockfish", "stockfish"]),
        ("deeplink", ["DeepLinkService", "app_links", "Intent.ACTION_VIEW"]),
        ("revenuecat", ["RevenueCat", "Purchases", "purchases_flutter"]),
        ("sentry-sdk", ["SentryFlutter", "SentryWidgetsBinding", "SentryCrash", "SentryANR"]),
    ]
    labels = [label for label, needles in rules if any(needle in haystack for needle in needles)]
    return labels or ["unclassified"]


def latest_event(api: SentryApi, issue_id: str) -> dict[str, Any] | None:
    # This endpoint is part of Sentry's public API surface even though docs search
    # sometimes returns the project-event endpoint first.
    event, _ = api.get(f"/api/0/issues/{issue_id}/events/latest/", tolerate_404=True)
    if isinstance(event, dict):
        return event
    events, _ = api.get(f"/api/0/issues/{issue_id}/events/", {"limit": 1}, tolerate_404=True)
    if isinstance(events, list) and events:
        first = events[0]
        return first if isinstance(first, dict) else None
    return None


def summarize_issue(api: SentryApi, issue: dict[str, Any]) -> dict[str, Any]:
    issue_id = str(issue.get("id"))
    event = latest_event(api, issue_id)
    tags = tag_map(event)
    contexts = (event or {}).get("contexts") or {}
    os_context = contexts.get("os") or {}
    device_context = contexts.get("device") or {}
    exception = exception_text(event)
    return {
        "id": issue_id,
        "shortId": issue.get("shortId"),
        "title": issue.get("title"),
        "culprit": issue.get("culprit"),
        "count": int(str(issue.get("count") or "0").replace(",", "") or "0"),
        "userCount": issue.get("userCount"),
        "firstSeen": issue.get("firstSeen"),
        "lastSeen": issue.get("lastSeen"),
        "permalink": issue.get("permalink"),
        "project": issue.get("project"),
        "platform": issue.get("platform"),
        "level": issue.get("level"),
        "classifications": classify(issue, event),
        "latestEvent": {
            "eventID": (event or {}).get("eventID"),
            "dateCreated": (event or {}).get("dateCreated"),
            "release": tags.get("release"),
            "environment": tags.get("environment"),
            "os": tags.get("os") or os_context.get("name"),
            "osVersion": tags.get("os.version") or os_context.get("version"),
            "device": tags.get("device") or device_context.get("model"),
            "deviceFamily": tags.get("device.family") or device_context.get("family"),
            "appVersion": tags.get("app.version"),
            "handled": tags.get("handled"),
            "mechanism": tags.get("mechanism"),
            "exceptionPreview": "\n".join(exception.splitlines()[:18]),
        },
    }


def markdown_report(
    rows: list[dict[str, Any]],
    *,
    org: str,
    project_id: str | None,
    stats_period: str,
) -> str:
    generated = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        for label in row["classifications"]:
            groups.setdefault(label, []).append(row)

    lines = [
        "# Sentry Crash Audit",
        "",
        f"- Generated: {generated}",
        f"- Org: {org}",
        f"- Project id filter: {project_id or 'not set'}",
        f"- Period: {stats_period}",
        f"- Issues returned: {len(rows)}",
        "",
        "## Classification Summary",
        "",
    ]
    for label, label_rows in sorted(groups.items(), key=lambda item: (-len(item[1]), item[0])):
        total = sum(int(row.get("count") or 0) for row in label_rows)
        users = sum(int(row.get("userCount") or 0) for row in label_rows if row.get("userCount") is not None)
        lines.append(f"- {label}: {len(label_rows)} issues, {total} events, {users} users")

    lines.extend(["", "## Issues", ""])
    for row in sorted(rows, key=lambda item: int(item.get("count") or 0), reverse=True):
        latest = row["latestEvent"]
        labels = ", ".join(row["classifications"])
        lines.extend(
            [
                f"### {row.get('shortId') or row['id']}: {row.get('title')}",
                "",
                f"- Classifications: {labels}",
                f"- Count/user count: {row.get('count')} / {row.get('userCount')}",
                f"- First/last seen: {row.get('firstSeen')} / {row.get('lastSeen')}",
                f"- Release/app version: {latest.get('release')} / {latest.get('appVersion')}",
                f"- OS/device: {latest.get('os')} {latest.get('osVersion')} / {latest.get('device') or latest.get('deviceFamily')}",
                f"- Handled/mechanism: {latest.get('handled')} / {latest.get('mechanism')}",
                f"- Link: {row.get('permalink')}",
                "",
            ]
        )
        preview = latest.get("exceptionPreview")
        if preview:
            lines.extend(["```", preview[:2000], "```", ""])
    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--org", default=getenv("SENTRY_ORG"))
    parser.add_argument("--project-id", default=getenv("SENTRY_PROJECT_ID") or dsn_project_id())
    parser.add_argument("--stats-period", default=getenv("SENTRY_STATS_PERIOD") or DEFAULT_STATS_PERIOD)
    parser.add_argument("--base-url", default=getenv("SENTRY_BASE_URL") or "https://sentry.io")
    parser.add_argument("--max-pages", type=int, default=5)
    parser.add_argument("--query", default=getenv("SENTRY_QUERY") or "")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = getenv("SENTRY_AUTH_TOKEN")
    if not token:
        print("Missing SENTRY_AUTH_TOKEN with event:read access.", file=sys.stderr)
        return 2

    api = SentryApi(args.base_url, token)
    org = args.org or discover_org(api)
    params: dict[str, Any] = {
        "statsPeriod": args.stats_period,
        "groupStatsPeriod": "auto",
        "query": args.query,
        "sort": "freq",
        "limit": 100,
        "collapse": ["stats"],
    }
    if args.project_id:
        params["project"] = args.project_id

    issues = api.get_pages(f"/api/0/organizations/{org}/issues/", params, max_pages=args.max_pages)
    rows = [summarize_issue(api, issue) for issue in issues if isinstance(issue, dict)]

    TMP_DIR.mkdir(exist_ok=True)
    suffix = args.stats_period.replace(" ", "_")
    json_path = TMP_DIR / f"sentry_crashes_{suffix}.json"
    md_path = TMP_DIR / f"sentry_crashes_{suffix}.md"
    json_path.write_text(json.dumps(rows, indent=2, sort_keys=True), encoding="utf-8")
    md_path.write_text(
        markdown_report(rows, org=org, project_id=args.project_id, stats_period=args.stats_period),
        encoding="utf-8",
    )
    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
