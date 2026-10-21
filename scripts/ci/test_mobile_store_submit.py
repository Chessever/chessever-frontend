"""Exercise store submission boundaries without credentials or network access."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("mobile_store_submit.sh").resolve()


class StoreSubmissionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.json"
        for name in ("google-play", "app-store-connect"):
            tool = self.bin / name
            tool.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['CALLS_FILE']).write_text(json.dumps(sys.argv))\n"
            )
            tool.chmod(0o700)
        self.env = {
            "PATH": f"{self.bin}{os.pathsep}{os.defpath}",
            "CALLS_FILE": str(self.calls),
            "GITHUB_REF": "refs/heads/stable",
        }

    def submit(self, platform, **env):
        return subprocess.run(
            ["bash", str(SCRIPT), platform],
            cwd=self.root,
            env={**self.env, **env},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_other_branches_cannot_submit(self):
        for platform in ("android", "ios"):
            result = self.submit(platform, GITHUB_REF="refs/heads/main")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.calls.exists())

    def test_android_without_publishing_confirmation_never_uploads(self):
        for confirmation in ("", "false"):
            result = self.submit(
                "android", MANAGED_PUBLISHING_CONFIRMED=confirmation
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.calls.exists())

    def test_android_submits_production_for_review_after_confirmation(self):
        result = self.submit("android", MANAGED_PUBLISHING_CONFIRMED="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.calls.read_text())
        self.assertEqual(args[1:3], ["bundles", "publish"])
        self.assertEqual(args[args.index("--track") + 1], "production")
        self.assertNotIn("--draft", args)
        self.assertNotIn("--changes-not-sent-for-review", args)

    def test_ios_submits_for_review_with_manual_release(self):
        ipa = self.root / "build/ios/ipa/ChessEver.ipa"
        ipa.parent.mkdir(parents=True)
        ipa.touch()
        result = self.submit("ios")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.calls.read_text())
        self.assertIn("--app-store", args)
        self.assertEqual(args[args.index("--release-type") + 1], "MANUAL")
        self.assertEqual(args[args.index("--platform") + 1], "IOS")
        self.assertNotIn("--cancel-previous-submissions", args)

    def test_ios_missing_or_ambiguous_ipa_never_uploads(self):
        self.assertNotEqual(self.submit("ios").returncode, 0)
        directory = self.root / "build/ios/ipa"
        directory.mkdir(parents=True)
        for name in ("first.ipa", "second.ipa"):
            (directory / name).touch()
        self.assertNotEqual(self.submit("ios").returncode, 0)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
