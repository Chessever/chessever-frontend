import unittest
from datetime import datetime, timezone

import telegram_run_updates as t

NOW = datetime(2026, 10, 31, 12, 30, tzinfo=timezone.utc)
CTX = {
    "title": "Mobile release",
    "detail": "37.6.14+3781 · Android + iOS",
    "sha": "99a22da3f00d",
    "subject": "fix: <tags> & things",
    "ref": "stable",
    "number": "58",
    "actor": "devberkay",
    "url": "https://github.com/Chessever/chessever-frontend/actions/runs/1",
}


def job(name, status, conclusion=None, steps=(), started="2026-10-31T12:00:00Z",
        completed=None):
    return {"name": name, "status": status, "conclusion": conclusion,
            "started_at": started, "completed_at": completed, "steps": list(steps)}


class JobStateTest(unittest.TestCase):
    def test_failed_step_shows_before_cleanup_finishes(self):
        running = job("iOS IPA", "in_progress", steps=[
            {"name": "Build IPA", "status": "completed", "conclusion": "failure"},
            {"name": "Remove signing material", "status": "in_progress", "conclusion": None},
        ])
        self.assertEqual(t.job_state(running), "failure")
        self.assertIn("failed at <i>Build IPA</i>", t.render_job(running, NOW))

    def test_approval_wait_and_skip(self):
        self.assertIn("waiting for approval", t.render_job(job("Android", "waiting"), NOW))
        skipped = job("Android", "completed", "skipped", completed="2026-10-31T12:00:00Z")
        self.assertEqual(t.render_job(skipped, NOW), "⏭ Android · skipped")

    def test_outcome_prefers_failure_then_cancel(self):
        ok = job("a", "completed", "success")
        self.assertEqual(t.run_outcome([ok, job("b", "completed", "skipped")]), "succeeded")
        self.assertEqual(t.run_outcome([ok, job("b", "completed", "cancelled")]), "cancelled")
        self.assertEqual(t.run_outcome([job("b", "completed", "cancelled"),
                                        job("c", "completed", "timed_out")]), "failed")

    def test_durations(self):
        done = job("a", "completed", "success", completed="2026-10-31T12:21:14Z")
        self.assertTrue(t.render_job(done, NOW).endswith("21m 14s"))
        running = job("b", "in_progress", steps=[{"name": "Build", "status": "in_progress"}])
        self.assertEqual(t.render_job(running, NOW), "⏳ b · Build · 30m")


class MessageTest(unittest.TestCase):
    def test_escapes_commit_text(self):
        text = t.render_message(CTX, [], "running", NOW)
        self.assertIn("fix: &lt;tags&gt; &amp; things", text)
        self.assertIn("🕓 starting", text)

    def test_final_header_carries_elapsed(self):
        text = t.render_message(CTX, [], "succeeded", NOW, "25m 3s")
        self.assertTrue(text.startswith("✅ <b>Mobile release</b> · succeeded in 25m 3s"))


if __name__ == "__main__":
    unittest.main()
