#!/usr/bin/env python3
"""Local-only editorial Inbox administration; offline preview is the default.

No dotenv loading, remote endpoints, redirects, proxies, push or email. The
service credential is read only at runtime, only for an explicitly applied
loopback operation, and is never logged. Python standard library only.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener
from uuid import UUID

TITLE_MAX = 200
BODY_MAX = 20000
FILE_MAX_BYTES = 100000
URL_ENV = "EDITORIAL_INBOX_LOCAL_URL"
KEY_ENV = "EDITORIAL_INBOX_LOCAL_SERVICE_ROLE_KEY"
AUDIENCE = "Everyone, including Supabase anonymous-auth guests. Inbox only; no push or email."


class InboxError(Exception):
    """Safe, credential-free error suitable for operator output."""


def validate_draft(data: Any) -> dict[str, str]:
    if not isinstance(data, dict) or set(data) != {"id", "title", "body"}:
        raise InboxError("Draft JSON must contain exactly id, title and body.")
    identifier = data["id"]
    if not isinstance(identifier, str) or not re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", identifier
    ) or str(UUID(identifier)) != identifier:
        raise InboxError("id must be an explicit canonical lowercase UUID; it is never repaired.")
    for name, maximum in (("title", TITLE_MAX), ("body", BODY_MAX)):
        value = data[name]
        if not isinstance(value, str) or not value.strip() or not 1 <= len(value) <= maximum:
            raise InboxError(f"{name} must be nonblank plain text of 1–{maximum} characters.")
        if "\x00" in value:
            raise InboxError(f"{name} cannot contain NUL characters.")
    if "\n" in data["title"] or "\r" in data["title"]:
        raise InboxError("title must be a single line.")
    return dict(data)


def read_text_file(path: Path) -> str:
    try:
        with path.open("rb") as stream:
            raw = stream.read(FILE_MAX_BYTES + 1)
        if len(raw) > FILE_MAX_BYTES:
            raise InboxError("Input file is too large.")
        return raw.decode("utf-8")
    except (OSError, UnicodeError) as exc:
        raise InboxError("Cannot read the UTF-8 input file.") from exc


def read_draft(path: Path) -> dict[str, str]:
    def unique_object(pairs):
        data = {}
        for key, value in pairs:
            if key in data:
                raise InboxError("Duplicate JSON fields are not allowed.")
            data[key] = value
        return data

    try:
        return validate_draft(json.loads(read_text_file(path), object_pairs_hook=unique_object))
    except json.JSONDecodeError as exc:
        raise InboxError("Draft is not valid JSON.") from exc


def local_base_url(value: str) -> str:
    """Validate before reading any credential; localhost is pinned, not resolved."""
    try:
        parsed = urlsplit(value)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            raise ValueError
        if parsed.username is not None or parsed.password is not None:
            raise ValueError
        if parsed.path not in ("", "/") or parsed.query or parsed.fragment:
            raise ValueError
        host = parsed.hostname
        if host == "localhost":
            host = "127.0.0.1"
        if not ipaddress.ip_address(host).is_loopback:
            raise ValueError
        port = parsed.port
        if port is not None and not 1 <= port <= 65535:
            raise ValueError
    except ValueError as exc:
        raise InboxError("Endpoint must be a literal loopback URL (or localhost), without credentials/path/query/fragment. Remote operation is disabled.") from exc
    authority = f"[{host}]" if ":" in host else host
    if port is not None:
        authority += f":{port}"
    return f"{parsed.scheme}://{authority}"


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise InboxError("API redirect refused; no credentials were forwarded.")


class LocalAPI:
    def __init__(self, base_url: str, key: str):
        self.base_url = local_base_url(base_url)
        if not key or any(c in key for c in "\r\n"):
            raise InboxError("A local service-role credential is required in the dedicated environment variable.")
        self._key = key
        # Disable ambient proxy settings so loopback credentials cannot leave
        # through an HTTP(S)_PROXY, even if NO_PROXY was absent or misconfigured.
        self._opener = build_opener(ProxyHandler({}), NoRedirects())

    def request(self, path: str, payload: dict[str, str] | None = None) -> Any:
        if not path.startswith("/rest/v1/") or "://" in path:
            raise InboxError("Invalid local API path.")
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        req = Request(self.base_url + path, data=data, headers={
            "apikey": self._key,
            "Authorization": f"Bearer {self._key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }, method="GET" if payload is None else "POST")
        try:
            with self._opener.open(req, timeout=10) as response:
                raw = response.read(200000 + 1)
            if len(raw) > 200000:
                raise InboxError("Local API response is too large.")
            return json.loads(raw)
        except HTTPError as exc:
            # Never print response bodies, URLs, request headers or credentials.
            raise InboxError(f"Local API rejected the operation (HTTP {exc.code}); no success claimed.") from None
        except (URLError, OSError) as exc:
            raise InboxError("Local API connection failed; no success claimed.") from exc
        except (ValueError, UnicodeError) as exc:
            raise InboxError("Local API returned invalid JSON; no success claimed.") from exc

    def fetch(self, identifier: str) -> dict[str, Any]:
        rows = self.request(
            "/rest/v1/editorial_inbox_messages?id=eq." + identifier +
            "&select=id,title,body,published_at,created_at"
        )
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
            raise InboxError("Expected exactly one saved message; no success claimed.")
        return rows[0]


def verify_row(row: Any, draft: dict[str, str], published: bool) -> dict[str, Any]:
    # PostgREST composite-returning RPCs normally return a one-element array;
    # an explicitly singular representation may return an object instead.
    if isinstance(row, list):
        if len(row) != 1:
            raise InboxError("Expected exactly one RPC message; no success claimed.")
        row = row[0]
    if not isinstance(row, dict) or not {"published_at", "created_at"}.issubset(row) or any(row.get(k) != v for k, v in draft.items()):
        raise InboxError("Saved content differs from the displayed draft; no success claimed.")
    timestamp = row["published_at"]
    for name, value in (("created_at", row["created_at"]), ("published_at", timestamp)):
        if name == "published_at" and value is None:
            continue
        try:
            if not isinstance(value, str) or datetime.fromisoformat(value).utcoffset() is None:
                raise ValueError
        except ValueError as exc:
            raise InboxError("Local API returned invalid server timestamps; no success claimed.") from exc
    if published and timestamp is None:
        raise InboxError("Publication was not confirmed; no success claimed.")
    if not published and timestamp is not None:
        raise InboxError("Message is already published and immutable; draft save not confirmed.")
    return row


def apply_operation(action: str, draft: dict[str, str], api: LocalAPI) -> dict[str, Any]:
    if action not in ("save", "publish"):
        raise InboxError("Only explicit save or publish operations are supported.")
    draft = validate_draft(draft)
    if action == "save":
        response = api.request("/rest/v1/rpc/save_editorial_inbox_draft", {
            "p_id": draft["id"], "p_title": draft["title"], "p_body": draft["body"],
        })
        verify_row(response, draft, published=False)
        return verify_row(api.fetch(draft["id"]), draft, published=False)
    # Preview the persisted snapshot too; SQL checks it atomically under lock.
    row = api.fetch(draft["id"])
    if any(row.get(k) != v for k, v in draft.items()):
        raise InboxError("Saved draft changed; preview and approve again before publishing.")
    response = api.request("/rest/v1/rpc/publish_editorial_inbox", {
        "p_id": draft["id"],
        "p_expected_title": draft["title"], "p_expected_body": draft["body"],
    })
    response = verify_row(response, draft, published=True)
    verified = verify_row(api.fetch(draft["id"]), draft, published=True)
    if verified["published_at"] != response["published_at"]:
        raise InboxError("Publication timestamp changed during verification; no success claimed.")
    return verified


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="action")
    create = sub.add_parser("create", help="Create a local draft file only; never calls the API.")
    create.add_argument("--id", required=True)
    create.add_argument("--title", required=True)
    create.add_argument("--body-file", type=Path, required=True)
    create.add_argument("--output", type=Path, required=True)
    for action in ("preview", "save", "publish"):
        command = sub.add_parser(action)
        command.add_argument("draft", type=Path)
        if action != "preview":
            command.add_argument("--apply", action="store_true", help="Explicitly perform the operation on loopback only.")
        if action == "publish":
            command.add_argument("--confirm-id", help="Must exactly match the displayed UUID when --apply is used.")
    return result


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    # `tool draft.json` means offline preview, not a network operation.
    if args and args[0] not in ("create", "preview", "save", "publish", "-h", "--help"):
        args.insert(0, "preview")
    argument_parser = parser()
    options = argument_parser.parse_args(args)
    if options.action is None:
        argument_parser.print_help()
        return 0
    try:
        if options.action == "create":
            draft = validate_draft({"id": options.id, "title": options.title,
                                    "body": read_text_file(options.body_file)})
            try:
                with options.output.open("x", encoding="utf-8") as stream:
                    json.dump(draft, stream, ensure_ascii=False, indent=2)
                    stream.write("\n")
            except OSError as exc:
                raise InboxError("Cannot create the local draft file (existing files are never overwritten).") from exc
            print("LOCAL DRAFT CREATED; not saved to the API and not published.")
        else:
            draft = read_draft(options.draft)
        print(f"Audience: {AUDIENCE}")
        print(json.dumps(draft, ensure_ascii=False, indent=2))
        if options.action in ("create", "preview") or not options.apply:
            print("OFFLINE PREVIEW ONLY. No API requests; nothing published.")
            return 0
        if options.action == "publish" and options.confirm_id != draft["id"]:
            raise InboxError("Publishing requires --confirm-id matching the exact draft UUID.")
        # Dedicated local env names prevent accidental use of app/production
        # dotenv config. Check the endpoint BEFORE retrieving the credential.
        base_url = local_base_url(os.environ.get(URL_ENV, ""))
        key = os.environ.get(KEY_ENV, "")
        row = apply_operation(options.action, draft, LocalAPI(base_url, key))
        if options.action == "save":
            print("LOCAL API DRAFT SAVED AND READ BACK; unpublished, no recipients notified.")
        else:
            print(f"LOCAL API PUBLICATION READ BACK: {row['id']} at {row['published_at']}. No push or email.")
        return 0
    except InboxError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
