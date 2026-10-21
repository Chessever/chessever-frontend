import copy
import unittest

from mobile_artifact_download import REPOSITORY, package_version, validate_source


class ArtifactSourceTest(unittest.TestCase):
    def setUp(self):
        self.sha = "a" * 40
        self.run = {
            "path": ".github/workflows/mobile-release.yml",
            "event": "workflow_dispatch", "head_branch": "stable",
            "status": "completed", "conclusion": "success",
            "head_sha": self.sha,
            "repository": {"full_name": REPOSITORY},
            "head_repository": {"full_name": REPOSITORY},
        }

    def test_exact_successful_production_source_is_accepted(self):
        validate_source(self.run, self.sha, "37.1.0+3709", "37.1.0+3709")

    def test_untrusted_or_failed_runs_are_rejected(self):
        for key, value in [
            ("path", ".github/workflows/pull-request.yml"),
            ("event", "pull_request"), ("head_branch", "dev"),
            ("status", "in_progress"), ("conclusion", "failure"),
            ("head_sha", "b" * 40),
        ]:
            run = {**self.run, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_source(run, self.sha, "37.1.0+3709", "37.1.0+3709")

    def test_foreign_artifact_sources_are_rejected(self):
        for key in ("repository", "head_repository"):
            run = copy.deepcopy(self.run)
            run[key]["full_name"] = "attacker/fork"
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_source(run, self.sha, "37.1.0+3709", "37.1.0+3709")

    def test_old_versions_or_missing_full_sha_are_rejected(self):
        for sha, source_version in [(self.sha, "37.0.8+3682"), ("main", "37.1.0+3709")]:
            with self.assertRaises(ValueError):
                validate_source(self.run, sha, "37.1.0+3709", source_version)

    def test_pubspec_version_parser_includes_build_number(self):
        self.assertEqual(package_version("name: app\nversion: 37.1.0+3709\n"), "37.1.0+3709")
        self.assertIsNone(package_version("name: app\n"))


if __name__ == "__main__":
    unittest.main()
