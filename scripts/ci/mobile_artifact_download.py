"""Download a reviewed production build from a successful trusted Actions run."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY = "Chessever/chessever-frontend"
DESTINATIONS = {
    "android": ("android-app-bundle", "build/app/outputs/bundle/productionRelease"),
    "ios": ("ios-ipa", "build/ios/ipa"),
}


def validate_source(run, expected_sha, version, source_version):
    required = {
        "path": ".github/workflows/mobile-release.yml",
        "event": "workflow_dispatch",
        "head_branch": "stable",
        "status": "completed",
        "conclusion": "success",
        "head_sha": expected_sha,
    }
    if not re.fullmatch(r"[0-9a-f]{40}", expected_sha):
        raise ValueError("A full reviewed source commit SHA is required")
    for key, expected in required.items():
        if run.get(key) != expected:
            raise ValueError(f"Source run has an unexpected {key}")
    for key in ("repository", "head_repository"):
        if run.get(key, {}).get("full_name") != REPOSITORY:
            raise ValueError("Source run must belong to the production repository")
    if not version or version != source_version:
        raise ValueError("Artifact version must match the current production version")


def package_version(text):
    match = re.search(r"^version:\s*(\S+)\s*$", text, re.MULTILINE)
    return match.group(1) if match else None


def gh_json(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def main():
    if os.environ.get("GITHUB_REF") != "refs/heads/stable":
        raise ValueError("Artifact submission must run from stable")
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise ValueError("Unexpected production repository")
    run_id = os.environ.get("SOURCE_RUN_ID", "")
    sha = os.environ.get("SOURCE_COMMIT", "")
    if not re.fullmatch(r"[0-9]+", run_id):
        raise ValueError("A numeric source run ID is required")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("A full reviewed source commit SHA is required")
    artifact, destination = DESTINATIONS[sys.argv[1]]
    run = gh_json(f"repos/{REPOSITORY}/actions/runs/{run_id}")
    source = subprocess.check_output([
        "gh", "api", f"repos/{REPOSITORY}/contents/pubspec.yaml?ref={sha}",
        "-H", "Accept: application/vnd.github.raw+json",
    ], text=True)
    validate_source(
        run, sha, package_version(Path("pubspec.yaml").read_text()),
        package_version(source),
    )
    subprocess.run([
        "gh", "run", "download", run_id, "--repo", REPOSITORY,
        "--name", artifact, "--dir", destination,
    ], check=True)
    print(f"Downloaded {artifact} from verified production run {run_id} ({sha}).")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, IndexError) as error:
        print(f"::error::{error}", file=sys.stderr)
        raise SystemExit(1) from error
