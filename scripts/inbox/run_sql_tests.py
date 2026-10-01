#!/usr/bin/env python3
"""Execute SQL against a new disposable LOCAL CONTRACT FIXTURE cluster.

Not hosted Supabase/PostgREST/JWT parity. Never accepts an existing DB URL,
credentials or remote host. PostgreSQL tools must already be installed or
unpacked locally; this runner never installs packages or changes global config.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def concurrent_contract_checks(psql: list[str], env: dict[str, str]) -> None:
    """Additional real multi-connection races, still LOCAL FIXTURE data only."""
    def query(statement: str) -> str:
        result = subprocess.run([*psql, "-c", statement], check=True,
                                capture_output=True, text=True, env=env)
        return result.stdout.strip()

    mark = """
      set role authenticated;
      set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
      begin;
      select public.mark_editorial_inbox_read('10000000-0000-4000-8000-000000000002');
      select pg_sleep(0.05);
      commit;
    """
    with ThreadPoolExecutor(max_workers=8) as executor:
        stamps = list(executor.map(query, [mark] * 8))
    if not stamps[0] or len(set(stamps)) != 1:
        raise RuntimeError("Concurrent first marks did not all return the same original timestamp")
    if query("select count(*) from public.editorial_inbox_reads where user_id = '22222222-2222-4222-8222-222222222222' and message_id = '10000000-0000-4000-8000-000000000002'") != "1":
        raise RuntimeError("Concurrent marks did not leave exactly one own row")

    query("set role service_role; select public.save_editorial_inbox_draft('60000000-0000-4000-8000-000000000001','[LOCAL TEST FIXTURE] Concurrent publish','Synthetic concurrent body');")
    publish = """
      set role service_role;
      begin;
      select (public.publish_editorial_inbox('60000000-0000-4000-8000-000000000001',
        '[LOCAL TEST FIXTURE] Concurrent publish','Synthetic concurrent body')).published_at;
      select pg_sleep(0.05);
      commit;
    """
    with ThreadPoolExecutor(max_workers=8) as executor:
        publications = list(executor.map(query, [publish] * 8))
    if not publications[0] or len(set(publications)) != 1:
        raise RuntimeError("Concurrent publication retries did not return the same original timestamp")
    if query("select count(*) from public.editorial_inbox_messages where id = '60000000-0000-4000-8000-000000000001' and published_at is not null") != "1":
        raise RuntimeError("Concurrent publications did not leave exactly one published message")
    print("4 additional real concurrency checks passed (8 simultaneous marks + 8 publications).")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, help="Directory containing initdb, pg_ctl, psql.")
    parser.add_argument("--pg-lib", type=Path, help="Unpacked libpq directory, if not installed.")
    parser.add_argument("--pg-share", type=Path, help="Unpacked PostgreSQL share directory.")
    args = parser.parse_args()
    tools = {}
    for name in ("initdb", "pg_ctl", "psql"):
        value = str(args.pg_bin / name) if args.pg_bin else shutil.which(name)
        if value is None or not Path(value).is_file():
            parser.error(f"PostgreSQL {name} unavailable; provide local --pg-bin.")
        tools[name] = str(Path(value).resolve())
    env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
    if args.pg_lib:
        env["LD_LIBRARY_PATH"] = str(args.pg_lib.resolve())
    # All transient files remain within this worktree and are removed on exit.
    local_runs = ROOT / "scripts/inbox/.local-postgres/runs"
    local_runs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="contract-fixture-", dir=local_runs) as temp:
        base = Path(temp)
        data = base / "data"
        init = [tools["initdb"], "-D", str(data), "--no-locale", "--encoding=UTF8",
                "--auth-local=trust", "--auth-host=trust", "--username=inbox_fixture_owner"]
        if args.pg_share:
            init += ["-L", str(args.pg_share.resolve())]
        subprocess.run(init, check=True, capture_output=True, text=True, env=env)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        # Private process; no Unix/global socket, and never listens externally.
        options = f"-F -p {port} -c listen_addresses=127.0.0.1 -c unix_socket_directories=''"
        started = False
        try:
            subprocess.run([tools["pg_ctl"], "-D", str(data), "-l", str(base / "postgres.log"),
                            "-w", "start", "-o", options], check=True, capture_output=True, text=True, env=env)
            started = True
            print("Running LOCAL CONTRACT FIXTURE only (disposable loopback PostgreSQL).")
            psql = [tools["psql"], "-X", "-q", "-t", "-A", "-h", "127.0.0.1", "-p", str(port),
                    "-U", "inbox_fixture_owner", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]
            result = subprocess.run([
                *psql, "-v", "editorial_inbox_local_fixture=on",
                "-f", str(ROOT / "supabase/tests/editorial_inbox.sql"),
            ], capture_output=True, text=True, env=env)
            for line in result.stdout.splitlines():
                if line.strip():
                    print(line)
            if result.stderr:
                print(result.stderr)
            if result.returncode != 0:
                return result.returncode
            concurrent_contract_checks(psql, env)
            print("Ephemeral PostgreSQL SQL checks passed; cluster will be stopped and removed.")
            return 0
        finally:
            if started:
                subprocess.run([tools["pg_ctl"], "-D", str(data), "-w", "stop", "-m", "immediate"],
                               check=True, capture_output=True, text=True, env=env)


if __name__ == "__main__":
    raise SystemExit(main())
