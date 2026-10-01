"""LOCAL API MOCK FIXTURE tests: real loopback HTTP, no Supabase/live backend.

Every token, body and timestamp below is synthetic test data. This does not
prove production PostgREST, JWT validation or deployed Supabase behavior.
"""
from __future__ import annotations

from contextlib import redirect_stdout, redirect_stderr
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import StringIO
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_inbox as inbox

HERE = Path(__file__).resolve().parent
FIXTURE_ID = "40000000-0000-4000-8000-000000000001"
OTHER_FIXTURE_ID = "40000000-0000-4000-8000-000000000002"
FIXTURE_KEY = "LOCAL_API_MOCK_FIXTURE_NOT_A_REAL_CREDENTIAL"
FIXTURE_DRAFT = {"id": FIXTURE_ID, "title": "[LOCAL TEST FIXTURE] Editorial title",
                 "body": "[LOCAL TEST FIXTURE] Plain text.\nSecond paragraph; <b>not interpreted</b>."}
FIXTURE_DATE = "2026-09-30T12:00:00+00:00"


class LocalMockFixture:
    def __init__(self):
        self.rows = {}
        self.requests = []
        self.behavior = None
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass  # Never log Authorization/apikey or URLs.

            def respond(self, status, value):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(value).encode())

            def do_GET(self):
                fixture.requests.append(("GET", self.path, None))
                if fixture.behavior == "redirect":
                    self.send_response(302)
                    self.send_header("Location", "https://non-loopback.example.invalid/leak")
                    self.end_headers()
                    return
                if fixture.behavior == "invalid_json":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"not json")
                    return
                if fixture.behavior == "get_500":
                    self.respond(500, {"secret": FIXTURE_KEY})
                    return
                query = parse_qs(urlsplit(self.path).query)
                identifier = query.get("id", [""])[0].removeprefix("eq.")
                row = fixture.rows.get(identifier)
                rows = [] if row is None else [dict(row)]
                if rows and fixture.behavior == "corrupt_read":
                    rows[0]["body"] = "[LOCAL TEST FIXTURE] Corrupted readback"
                if rows and fixture.behavior == "unpublished_read":
                    rows[0]["published_at"] = None
                self.respond(200, rows)

            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                payload = json.loads(raw)
                fixture.requests.append(("POST", self.path, payload))
                if self.headers.get("apikey") != FIXTURE_KEY or self.headers.get("Authorization") != f"Bearer {FIXTURE_KEY}":
                    self.respond(403, {"fixture": "incorrect test authentication"})
                    return
                if fixture.behavior == "post_500":
                    self.respond(500, {"secret": FIXTURE_KEY})
                    return
                if self.path == "/rest/v1/rpc/save_editorial_inbox_draft":
                    identifier = payload["p_id"]
                    old = fixture.rows.get(identifier)
                    if old and old["published_at"] is not None:
                        self.respond(409, {"fixture": "published immutable"})
                        return
                    draft = inbox.validate_draft({"id": identifier, "title": payload["p_title"], "body": payload["p_body"]})
                    row = dict(draft, published_at=None, created_at=FIXTURE_DATE)
                    fixture.rows[identifier] = row
                elif self.path == "/rest/v1/rpc/publish_editorial_inbox":
                    row = fixture.rows.get(payload["p_id"])
                    if row is None:
                        self.respond(404, {"fixture": "missing"})
                        return
                    if fixture.behavior == "concurrent_edit":
                        row["body"] = "[LOCAL TEST FIXTURE] Concurrent draft edit"
                    if row["title"] != payload["p_expected_title"] or row["body"] != payload["p_expected_body"]:
                        self.respond(409, {"fixture": "approved snapshot changed"})
                        return
                    if row["published_at"] is None:
                        row["published_at"] = FIXTURE_DATE
                else:
                    self.respond(404, {"fixture": "unsupported route"})
                    return
                result = dict(row)
                if fixture.behavior == "corrupt_rpc":
                    result["id"] = OTHER_FIXTURE_ID
                # LOCAL MOCK of PostgREST composite RPC representation.
                self.respond(200, [result])

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class ValidationTests(unittest.TestCase):
    def test_fixture_is_plain_text_and_preserved(self):
        self.assertEqual(inbox.validate_draft(FIXTURE_DRAFT), FIXTURE_DRAFT)

    def test_title_and_body_boundaries(self):
        inbox.validate_draft(dict(FIXTURE_DRAFT, title="t" * 200, body="b" * 20000))
        for changes in ({"title": "t" * 201}, {"body": "b" * 20001}):
            with self.subTest(changes=list(changes)), self.assertRaises(inbox.InboxError):
                inbox.validate_draft(dict(FIXTURE_DRAFT, **changes))

    def test_empty_blank_or_non_text_rejected(self):
        for name in ("title", "body"):
            for value in (None, 8, "", " \n\t", "\x00"):
                with self.subTest(name=name, value=value), self.assertRaises(inbox.InboxError):
                    inbox.validate_draft(dict(FIXTURE_DRAFT, **{name: value}))

    def test_multiline_title_rejected(self):
        for title in ("title\nother", "title\rother"):
            with self.subTest(title=title), self.assertRaises(inbox.InboxError):
                inbox.validate_draft(dict(FIXTURE_DRAFT, title=title))

    def test_uuid_not_repaired_or_generated(self):
        for identifier in (None, "bad", FIXTURE_ID.replace("-", ""), " " + FIXTURE_ID,
                           "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa".upper()):
            with self.subTest(identifier=identifier), self.assertRaises(inbox.InboxError):
                inbox.validate_draft(dict(FIXTURE_DRAFT, id=identifier))

    def test_unknown_fields_rejected(self):
        for extra in ("published_at", "created_at", "recipients", "user_id", "push"):
            with self.subTest(extra=extra), self.assertRaises(inbox.InboxError):
                inbox.validate_draft(dict(FIXTURE_DRAFT, **{extra: "forbidden"}))

    def test_missing_fields_and_array_rejected(self):
        for data in ({}, {"id": FIXTURE_ID}, [], None):
            with self.subTest(data=data), self.assertRaises(inbox.InboxError):
                inbox.validate_draft(data)

    def test_loopback_accepts_ipv4_ipv6_and_pinned_localhost(self):
        self.assertEqual(inbox.local_base_url("http://localhost:54321/"), "http://127.0.0.1:54321")
        self.assertEqual(inbox.local_base_url("http://127.0.0.1:1234"), "http://127.0.0.1:1234")
        self.assertEqual(inbox.local_base_url("https://[::1]:1234"), "https://[::1]:1234")

    def test_remote_and_ambiguous_urls_rejected(self):
        for url in ("", "https://project.supabase.co", "http://192.168.1.1:54321",
                    "http://0.0.0.0", "http://169.254.169.254", "http://localhost.attacker.test",
                    "http://127.0.0.1.attacker.test", "http://2130706433", "file:///a", "ftp://127.0.0.1",
                    "http://user:password@127.0.0.1", "http://127.0.0.1/rest/v1",
                    "http://127.0.0.1?q=x", "http://127.0.0.1#fragment", "http://127.0.0.1:99999"):
            with self.subTest(url=url), self.assertRaises(inbox.InboxError):
                inbox.local_base_url(url)

    def test_rpc_array_and_singular_representations(self):
        row = dict(FIXTURE_DRAFT, created_at=FIXTURE_DATE, published_at=None)
        self.assertEqual(inbox.verify_row([row], FIXTURE_DRAFT, False), row)
        self.assertEqual(inbox.verify_row(row, FIXTURE_DRAFT, False), row)

    def test_rpc_missing_or_multiple_rows_rejected(self):
        row = dict(FIXTURE_DRAFT, created_at=FIXTURE_DATE, published_at=None)
        for value in ([], [row, row], [None], "invalid"):
            with self.subTest(value=value), self.assertRaises(inbox.InboxError):
                inbox.verify_row(value, FIXTURE_DRAFT, False)

    def test_missing_and_invalid_server_timestamps_rejected(self):
        for value in (dict(FIXTURE_DRAFT), dict(FIXTURE_DRAFT, published_at=None, created_at="yesterday"),
                      dict(FIXTURE_DRAFT, published_at=None, created_at="2026-09-30T12:00:00"),
                      dict(FIXTURE_DRAFT, published_at=3, created_at=FIXTURE_DATE)):
            with self.subTest(value=value), self.assertRaises(inbox.InboxError):
                inbox.verify_row(value, FIXTURE_DRAFT, False)

    def test_unsupported_direct_operation_never_sends(self):
        with self.assertRaises(inbox.InboxError):
            inbox.apply_operation("delete", FIXTURE_DRAFT, None)

    def test_invalid_header_credential_rejected(self):
        for key in ("", "foo\nbar", "foo\rbar"):
            with self.subTest(key=key), self.assertRaises(inbox.InboxError):
                inbox.LocalAPI("http://127.0.0.1:54321", key)


class CLITests(unittest.TestCase):
    def setUp(self):
        local_runs = HERE / ".test-runs"
        local_runs.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="local-api-fixture-", dir=local_runs)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.draft_file = self.base / "draft.json"
        self.draft_file.write_text(json.dumps(FIXTURE_DRAFT), encoding="utf-8")

    def invoke(self, args, env=None):
        out, err = StringIO(), StringIO()
        with patch.dict(os.environ, env or {}, clear=True), redirect_stdout(out), redirect_stderr(err):
            code = inbox.main([str(x) for x in args])
        return code, out.getvalue(), err.getvalue()

    def fixture_env(self, server):
        return {inbox.URL_ENV: server.base_url, inbox.KEY_ENV: FIXTURE_KEY}

    def api(self, server):
        return inbox.LocalAPI(server.base_url, FIXTURE_KEY)

    def test_default_preview_no_network_or_service_environment_reads(self):
        original_get = inbox.os.environ.get

        def no_service_env(key, default=None):
            if key in (inbox.URL_ENV, inbox.KEY_ENV):
                raise AssertionError("offline preview must not read service env")
            return original_get(key, default)

        with patch.object(inbox.os.environ, "get", side_effect=no_service_env):
            out = StringIO()
            with redirect_stdout(out):
                self.assertEqual(inbox.main([str(self.draft_file)]), 0)
        self.assertIn("OFFLINE PREVIEW ONLY", out.getvalue())
        self.assertIn("guests", out.getvalue())
        self.assertIn("no push or email", out.getvalue())

    def test_save_and_publish_without_apply_are_offline(self):
        for action in ("save", "publish"):
            with self.subTest(action=action):
                code, out, err = self.invoke([action, self.draft_file])
                self.assertEqual(code, 0, err)
                self.assertIn("OFFLINE PREVIEW ONLY", out)

    def test_local_create_validates_and_never_overwrites(self):
        body = self.base / "fixture_body.txt"
        body.write_text(FIXTURE_DRAFT["body"], encoding="utf-8")
        target = self.base / "created.json"
        args = ["create", "--id", FIXTURE_ID, "--title", FIXTURE_DRAFT["title"],
                "--body-file", body, "--output", target]
        code, out, err = self.invoke(args)
        self.assertEqual(code, 0, err)
        self.assertIn("LOCAL DRAFT CREATED", out)
        self.assertEqual(inbox.read_draft(target), FIXTURE_DRAFT)
        code, _, err = self.invoke(args)
        self.assertEqual(code, 1)
        self.assertIn("never overwritten", err)
        self.assertEqual(inbox.read_draft(target), FIXTURE_DRAFT)

    def test_invalid_json_and_oversize_input(self):
        for raw in ("not json", "x" * (inbox.FILE_MAX_BYTES + 1)):
            with self.subTest(size=len(raw)):
                self.draft_file.write_text(raw, encoding="utf-8")
                self.assertEqual(self.invoke([self.draft_file])[0], 1)

    def test_duplicate_json_fields_not_silently_repaired(self):
        self.draft_file.write_text('{"id":"' + FIXTURE_ID + '","title":"first","title":"second","body":"[LOCAL TEST FIXTURE] body"}', encoding="utf-8")
        code, _, err = self.invoke([self.draft_file])
        self.assertEqual(code, 1)
        self.assertIn("Duplicate JSON fields", err)

    def test_non_utf8_input(self):
        self.draft_file.write_bytes(b"\xff")
        self.assertEqual(self.invoke([self.draft_file])[0], 1)

    def test_missing_file(self):
        self.assertEqual(self.invoke([self.base / "does-not-exist.json"])[0], 1)

    def test_publish_requires_exact_uuid_confirmation_before_network(self):
        with LocalMockFixture() as server:
            for confirm in (None, OTHER_FIXTURE_ID, " " + FIXTURE_ID):
                args = ["publish", self.draft_file, "--apply"]
                if confirm is not None:
                    args += ["--confirm-id", confirm]
                code, _, err = self.invoke(args, self.fixture_env(server))
                self.assertEqual(code, 1)
                self.assertIn("exact draft UUID", err)
            self.assertEqual(server.requests, [])

    def test_remote_endpoint_refused_and_credential_not_leaked(self):
        code, _, err = self.invoke(["save", self.draft_file, "--apply"], {
            inbox.URL_ENV: "https://project.supabase.co", inbox.KEY_ENV: FIXTURE_KEY})
        self.assertEqual(code, 1)
        self.assertIn("Remote operation is disabled", err)
        self.assertNotIn(FIXTURE_KEY, err)

    def test_missing_local_environment_fails_closed(self):
        self.assertEqual(self.invoke(["save", self.draft_file, "--apply"])[0], 1)
        self.assertEqual(self.invoke(["save", self.draft_file, "--apply"], {
            inbox.URL_ENV: "http://127.0.0.1:54321"})[0], 1)

    def test_save_and_retry_real_loopback_readback(self):
        with LocalMockFixture() as server:
            for _ in range(2):
                code, out, err = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
                self.assertEqual(code, 0, err)
                self.assertIn("DRAFT SAVED AND READ BACK", out)
            self.assertEqual(len(server.rows), 1)
            self.assertIsNone(server.rows[FIXTURE_ID]["published_at"])
            self.assertEqual([r[0] for r in server.requests], ["POST", "GET", "POST", "GET"])
            self.assertEqual(server.requests[0][2], {
                "p_id": FIXTURE_ID, "p_title": FIXTURE_DRAFT["title"], "p_body": FIXTURE_DRAFT["body"]})

    def test_publish_is_separate_specific_only_and_idempotent(self):
        with LocalMockFixture() as server:
            inbox.apply_operation("save", FIXTURE_DRAFT, self.api(server))
            server.rows[OTHER_FIXTURE_ID] = dict(FIXTURE_DRAFT, id=OTHER_FIXTURE_ID,
                                               created_at=FIXTURE_DATE, published_at=None)
            for _ in range(2):
                code, out, err = self.invoke(["publish", self.draft_file, "--apply", "--confirm-id", FIXTURE_ID], self.fixture_env(server))
                self.assertEqual(code, 0, err)
                self.assertIn("PUBLICATION READ BACK", out)
                self.assertIn("No push or email", out)
            self.assertEqual(server.rows[FIXTURE_ID]["published_at"], FIXTURE_DATE)
            self.assertIsNone(server.rows[OTHER_FIXTURE_ID]["published_at"])
            posts = [r for r in server.requests if r[1].endswith("publish_editorial_inbox")]
            self.assertEqual(len(posts), 2)
            self.assertEqual(posts[0][2], {"p_id": FIXTURE_ID, "p_expected_title": FIXTURE_DRAFT["title"], "p_expected_body": FIXTURE_DRAFT["body"]})
            self.assertTrue(all(r[1].startswith("/rest/v1/editorial_inbox_messages") or
                                r[1].startswith("/rest/v1/rpc/") for r in server.requests))

    def test_publish_missing_draft_never_creates_one(self):
        with LocalMockFixture() as server:
            code, out, _ = self.invoke(["publish", self.draft_file, "--apply", "--confirm-id", FIXTURE_ID], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertNotIn("PUBLICATION READ BACK", out)
            self.assertEqual(server.rows, {})
            self.assertTrue(all(r[0] == "GET" for r in server.requests))

    def test_changed_saved_draft_not_published(self):
        with LocalMockFixture() as server:
            server.rows[FIXTURE_ID] = dict(FIXTURE_DRAFT, title="[LOCAL TEST FIXTURE] Changed", created_at=FIXTURE_DATE, published_at=None)
            code, _, err = self.invoke(["publish", self.draft_file, "--apply", "--confirm-id", FIXTURE_ID], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertIn("preview and approve again", err)
            self.assertIsNone(server.rows[FIXTURE_ID]["published_at"])
            self.assertEqual(len(server.requests), 1)

    def test_concurrent_edit_during_publish_rejected_by_expected_snapshot(self):
        with LocalMockFixture() as server:
            inbox.apply_operation("save", FIXTURE_DRAFT, self.api(server))
            server.behavior = "concurrent_edit"
            code, out, _ = self.invoke(["publish", self.draft_file, "--apply", "--confirm-id", FIXTURE_ID], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertNotIn("PUBLICATION READ BACK", out)
            self.assertIsNone(server.rows[FIXTURE_ID]["published_at"])

    def test_published_content_cannot_be_saved(self):
        with LocalMockFixture() as server:
            server.rows[FIXTURE_ID] = dict(FIXTURE_DRAFT, created_at=FIXTURE_DATE, published_at=FIXTURE_DATE)
            code, out, err = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertIn("HTTP 409", err)
            self.assertNotIn("DRAFT SAVED", out)

    def test_save_readback_mismatch_no_false_success(self):
        with LocalMockFixture() as server:
            server.behavior = "corrupt_read"
            code, out, err = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertIn("no success claimed", err)
            self.assertNotIn("DRAFT SAVED", out)

    def test_rpc_response_mismatch_no_false_success(self):
        with LocalMockFixture() as server:
            server.behavior = "corrupt_rpc"
            code, out, _ = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertNotIn("DRAFT SAVED", out)
            self.assertEqual(len(server.requests), 1)

    def test_api_error_response_body_never_discloses_credential(self):
        with LocalMockFixture() as server:
            server.behavior = "post_500"
            code, out, err = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertNotIn(FIXTURE_KEY, out + err)
            self.assertNotIn("DRAFT SAVED", out)

    def test_readback_http_failure_no_false_success(self):
        with LocalMockFixture() as server:
            server.behavior = "get_500"
            code, out, err = self.invoke(["save", self.draft_file, "--apply"], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertNotIn("DRAFT SAVED", out)
            self.assertNotIn(FIXTURE_KEY, out + err)

    def test_redirect_is_refused_without_forwarding(self):
        with LocalMockFixture() as server:
            server.behavior = "redirect"
            with self.assertRaisesRegex(inbox.InboxError, "redirect refused"):
                self.api(server).fetch(FIXTURE_ID)
            self.assertEqual(len(server.requests), 1)

    def test_ambient_proxy_is_disabled(self):
        with LocalMockFixture() as server, patch.dict(os.environ, {
            "http_proxy": "http://non-loopback.example.invalid:9", "https_proxy": "http://non-loopback.example.invalid:9", "NO_PROXY": ""}, clear=True):
            result = inbox.apply_operation("save", FIXTURE_DRAFT, self.api(server))
            self.assertEqual(result["id"], FIXTURE_ID)

    def test_invalid_json_response_fails_closed(self):
        with LocalMockFixture() as server:
            server.behavior = "invalid_json"
            with self.assertRaisesRegex(inbox.InboxError, "invalid JSON"):
                self.api(server).fetch(FIXTURE_ID)

    def test_disconnected_local_endpoint_fails_closed(self):
        # Obtain a socket port, then close without running a server.
        with LocalMockFixture() as server:
            endpoint = server.base_url
        with self.assertRaisesRegex(inbox.InboxError, "connection failed"):
            inbox.LocalAPI(endpoint, FIXTURE_KEY).fetch(FIXTURE_ID)

    def test_publication_readback_not_published_no_false_success(self):
        with LocalMockFixture() as server:
            inbox.apply_operation("save", FIXTURE_DRAFT, self.api(server))
            server.behavior = "unpublished_read"
            code, out, err = self.invoke(["publish", self.draft_file, "--apply", "--confirm-id", FIXTURE_ID], self.fixture_env(server))
            self.assertEqual(code, 1)
            self.assertIn("not confirmed", err)
            self.assertNotIn("PUBLICATION READ BACK", out)

    def test_no_action_prints_help_and_never_requests(self):
        code, out, err = self.invoke([])
        self.assertEqual(code, 0, err)
        self.assertIn("loopback", out)

    def test_cli_subprocess_end_to_end_loopback_fixture(self):
        with LocalMockFixture() as server:
            env = dict(os.environ, **self.fixture_env(server))
            for command in ([str(self.draft_file)], ["save", str(self.draft_file), "--apply"],
                            ["publish", str(self.draft_file), "--apply", "--confirm-id", FIXTURE_ID]):
                result = subprocess.run([sys.executable, str(HERE / "publish_inbox.py"), *command],
                                        capture_output=True, text=True, env=env, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn(FIXTURE_KEY, result.stdout + result.stderr)
            self.assertEqual(server.rows[FIXTURE_ID]["published_at"], FIXTURE_DATE)


if __name__ == "__main__":
    unittest.main()
