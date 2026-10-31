#!/usr/bin/env python3
"""Post a GitHub Actions run to the team Telegram chat as one live message.

  watch   Run as its own job beside the others. Posts one message, edits it
          as each job is queued, waits for approval, runs and finishes, then
          replies once with the result (edits do not notify phones).
  report  One-shot, from a step inside a job (e.g. `if: failure()`). Posts the
          run's current state with the outcome given in OUTCOME.

This job is the only writer, so parallel jobs never overwrite each other.

Environment: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID (organization secrets),
GH_TOKEN (github.token with `actions: read`), and the standard GITHUB_*
variables. Optional: TITLE (defaults to the workflow name), DETAIL (one line
under the title), SELF_JOB (this job's display name, excluded from the list),
OUTCOME (report mode), TELEGRAM_DRY_RUN=1 to print instead of sending.

The bot token never reaches the log: it is only used inside request URLs, and
every error is reported without the URL.
"""

from __future__ import annotations

import html
import json
import os
import re
import signal
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

POLL_SECONDS = 20
# Dependent jobs appear only after their `needs` finish, so a run counts as
# done once every listed job has stayed completed for this many polls.
SETTLE_POLLS = 3
FAILED = {"failure", "timed_out", "startup_failure"}


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def format_duration(seconds: float, precise: bool) -> str:
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {secs}s" if precise else f"{minutes}m"
    return f"{secs}s" if precise else "<1m"


def _failed_step(job: dict) -> str | None:
    for step in job.get("steps") or []:
        if step.get("conclusion") in FAILED:
            return step.get("name")
    return None


def _running_step(job: dict) -> str | None:
    for step in job.get("steps") or []:
        if step.get("status") == "in_progress":
            return step.get("name")
    return None


def job_state(job: dict) -> str:
    """success | failure | cancelled | skipped | waiting | queued | running."""
    status = job.get("status")
    conclusion = job.get("conclusion")
    if status == "completed":
        if conclusion in FAILED:
            return "failure"
        if conclusion in ("success", "neutral"):
            return "success"
        if conclusion == "skipped":
            return "skipped"
        return "cancelled"
    # A job keeps running its cleanup steps after one fails; show it failed now.
    if _failed_step(job):
        return "failure"
    if status == "waiting":
        return "waiting"
    if status == "in_progress":
        return "running"
    return "queued"


ICONS = {
    "success": "✅",
    "failure": "❌",
    "cancelled": "⛔",
    "skipped": "⏭",
    "waiting": "⏸",
    "queued": "🕓",
    "running": "⏳",
}


def render_job(job: dict, now: datetime) -> str:
    state = job_state(job)
    name = html.escape(job.get("name") or "job")
    started = _parse_time(job.get("started_at"))
    completed = _parse_time(job.get("completed_at"))
    parts = [f"{ICONS[state]} {name}"]
    if state == "failure":
        step = _failed_step(job)
        if step:
            parts.append(f"failed at <i>{html.escape(step)}</i>")
    elif state == "running":
        step = _running_step(job)
        if step:
            parts.append(html.escape(step))
    elif state == "waiting":
        parts.append("waiting for approval")
    elif state in ("skipped", "cancelled", "queued"):
        parts.append(state)
    if started and state not in ("skipped", "queued", "waiting"):
        end = completed if job.get("status") == "completed" and completed else now
        parts.append(format_duration((end - started).total_seconds(),
                                     precise=job.get("status") == "completed"))
    return " · ".join(parts)


def run_outcome(jobs: list[dict]) -> str:
    states = [job_state(job) for job in jobs]
    if "failure" in states:
        return "failed"
    if "cancelled" in states:
        return "cancelled"
    return "succeeded"


HEADER_ICONS = {"running": "⏳", "succeeded": "✅", "failed": "❌", "cancelled": "⛔"}


def render_message(ctx: dict, jobs: list[dict], outcome: str, now: datetime,
                   elapsed: str | None = None) -> str:
    title = html.escape(ctx["title"])
    header = f"{HEADER_ICONS[outcome]} <b>{title}</b> · {outcome}"
    if elapsed and outcome != "running":
        header += f" in {elapsed}"
    lines = [header]
    if ctx.get("detail"):
        lines.append(html.escape(ctx["detail"]))
    commit = f"<code>{html.escape(ctx['sha'][:8])}</code>"
    if ctx.get("subject"):
        commit += f" {html.escape(ctx['subject'])}"
    lines.append(f"{commit} · {html.escape(ctx['ref'])}")
    lines.append("")
    if jobs:
        lines.extend(render_job(job, now) for job in jobs)
    else:
        lines.append("🕓 starting")
    lines.append("")
    lines.append(f'<a href="{html.escape(ctx["url"], quote=True)}">Run #{ctx["number"]}</a>'
                 f" · {html.escape(ctx['actor'])}")
    return "\n".join(lines)


class Telegram:
    def __init__(self, token: str, chat_id: str, dry_run: bool):
        self.token = token
        self.chat_id = chat_id
        self.dry_run = dry_run

    def call(self, method: str, payload: dict) -> dict | None:
        if self.dry_run:
            print(f"--- telegram {method} ---\n{payload.get('text', '')}\n")
            return {"message_id": 1}
        body = json.dumps({"chat_id": self.chat_id, **payload}).encode()
        request = urllib.request.Request(
            f"https://api.telegram.org/bot{self.token}/{method}",
            data=body, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.load(response).get("result")
        except urllib.error.HTTPError as error:
            # The description is safe to log; the URL (with the token) is not.
            try:
                detail = json.load(error).get("description", "")
            except ValueError:
                detail = ""
            if "message is not modified" not in detail:
                print(f"Telegram {method} failed: {error.code} {detail}", file=sys.stderr)
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            print(f"Telegram {method} failed: {type(error).__name__}", file=sys.stderr)
        return None

    def send(self, text: str, reply_to: int | None = None) -> int | None:
        payload = {"text": text, "parse_mode": "HTML",
                   "link_preview_options": {"is_disabled": True}}
        if reply_to:
            payload["reply_parameters"] = {"message_id": reply_to,
                                           "allow_sending_without_reply": True}
        result = self.call("sendMessage", payload)
        return result.get("message_id") if result else None

    def edit(self, message_id: int, text: str) -> None:
        self.call("editMessageText", {"message_id": message_id, "text": text,
                                      "parse_mode": "HTML",
                                      "link_preview_options": {"is_disabled": True}})


def github_get(path: str) -> dict | None:
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    request = urllib.request.Request(f"{api}/{path}", headers={
        "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        print(f"GitHub API {path.split('?')[0]} failed: {error}", file=sys.stderr)
        return None


def read_version() -> str | None:
    try:
        with open("pubspec.yaml", encoding="utf-8") as handle:
            match = re.search(r"^version:\s*(\S+)", handle.read(), re.MULTILINE)
            return match.group(1) if match else None
    except OSError:
        return None


def context() -> dict:
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = os.environ["GITHUB_RUN_ID"]
    sha = os.environ.get("GITHUB_SHA", "")
    commit = github_get(f"repos/{repo}/commits/{sha}") or {}
    subject = (commit.get("commit", {}).get("message") or "").split("\n", 1)[0]
    if len(subject) > 90:
        subject = subject[:89] + "…"
    run = github_get(f"repos/{repo}/actions/runs/{run_id}") or {}
    detail = os.environ.get("DETAIL", "").strip()
    version = read_version()
    if version:
        detail = f"{version} · {detail}" if detail else version
    return {
        "repo": repo,
        "run_id": run_id,
        "attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "title": os.environ.get("TITLE") or os.environ.get("GITHUB_WORKFLOW", "Workflow"),
        "detail": detail,
        "sha": sha,
        "subject": subject,
        "ref": os.environ.get("GITHUB_REF_NAME", ""),
        "number": os.environ.get("GITHUB_RUN_NUMBER", run_id),
        "actor": os.environ.get("GITHUB_ACTOR", ""),
        "run_started": _parse_time(run.get("run_started_at")),
        "url": f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}"
               f"/actions/runs/{run_id}",
    }


def fetch_jobs(ctx: dict) -> list[dict] | None:
    data = github_get(f"repos/{ctx['repo']}/actions/runs/{ctx['run_id']}"
                      f"/attempts/{ctx['attempt']}/jobs?per_page=100")
    if data is None:
        return None
    self_job = os.environ.get("SELF_JOB", "")
    jobs = [job for job in data.get("jobs", []) if job.get("name") != self_job]
    return sorted(jobs, key=lambda job: (job.get("created_at") or "", job.get("id", 0)))


def watch(ctx: dict, telegram: Telegram) -> None:
    started = ctx.get("run_started") or datetime.now(timezone.utc)
    message_id: int | None = None
    last_text = ""
    jobs: list[dict] = []
    settled = 0

    def post(text: str) -> None:
        nonlocal message_id, last_text
        if text == last_text:
            return
        if message_id is None:
            message_id = telegram.send(text)
        else:
            telegram.edit(message_id, text)
        last_text = text

    def finish(outcome: str) -> None:
        now = datetime.now(timezone.utc)
        elapsed = format_duration((now - started).total_seconds(), precise=True)
        post(render_message(ctx, jobs, outcome, now, elapsed))
        title = html.escape(ctx["title"])
        version = read_version()
        version = f" {html.escape(version)}" if version else ""
        telegram.send(f"{HEADER_ICONS[outcome]} {title}{version} {outcome} in {elapsed}",
                      reply_to=message_id)

    def on_cancel(signum, frame):  # noqa: ARG001 - signal handler signature
        finish("cancelled")
        sys.exit(0)

    signal.signal(signal.SIGTERM, on_cancel)
    signal.signal(signal.SIGINT, on_cancel)

    while True:
        fetched = fetch_jobs(ctx)
        if fetched is not None:
            jobs = fetched
        now = datetime.now(timezone.utc)
        done = bool(jobs) and all(job.get("status") == "completed" for job in jobs)
        settled = settled + 1 if done else 0
        if settled >= SETTLE_POLLS:
            break
        post(render_message(ctx, jobs, "running", now))
        time.sleep(POLL_SECONDS)

    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    finish(run_outcome(jobs))


def report(ctx: dict, telegram: Telegram) -> None:
    outcome = os.environ.get("OUTCOME", "failed")
    if outcome not in HEADER_ICONS:
        outcome = "failed"
    jobs = fetch_jobs(ctx) or []
    telegram.send(render_message(ctx, jobs, outcome, datetime.now(timezone.utc)))


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "watch"
    dry_run = os.environ.get("TELEGRAM_DRY_RUN") == "1"
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not dry_run and (not token or not chat_id):
        # Forks and repositories without the organization secrets: stay quiet.
        print("Telegram secrets are not available; skipping notifications.")
        return 0
    telegram = Telegram(token, chat_id, dry_run)
    ctx = context()
    if mode == "watch":
        watch(ctx, telegram)
    elif mode == "report":
        report(ctx, telegram)
    else:
        print(f"Unknown mode {mode!r}; use watch or report.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
