"""TestFlight uploads go to the production app once and never touch App Review."""
import io
from contextlib import redirect_stdout
import json
import unittest

from app_store_review import ReviewError
from test_app_store_review import AppleFixture
from testflight_upload import upload


class TestFlightUploadTest(unittest.TestCase):
    def run_upload(self, fixture, sleeps=None):
        sleeps = [] if sleeps is None else sleeps
        with redirect_stdout(io.StringIO()) as output:
            upload(fixture, 'fixture.ipa', '37.1.1', '3710', fixture.publisher, sleeps.append)
        return output.getvalue()

    def test_new_build_uploads_once_without_review_flags(self):
        api = AppleFixture(uploaded=False)
        output = self.run_upload(api)
        self.assertEqual(api.commands, [['publish', '--path', 'fixture.ipa']])
        self.assertFalse([r for r in api.requests if r[0] != 'GET'])
        receipt = json.loads(output.strip().splitlines()[-1])
        self.assertEqual(receipt['destination'], 'TestFlight')
        self.assertEqual((receipt['version'], receipt['build']), ('37.1.1', '3710'))

    def test_retry_of_uploaded_build_does_not_upload_again(self):
        api = AppleFixture(uploaded=True)
        self.run_upload(api)
        self.assertEqual(api.commands, [])

    def test_publisher_error_after_apple_received_the_package_is_not_a_failure(self):
        # Xcode 27's altool output reads as a failure to codemagic-cli-tools even
        # when the upload went through (39.2.0). Apple's upload record decides.
        api = AppleFixture(uploaded=False)
        api.publisher_fails = True
        api.upload_record = 'PROCESSING'
        output = self.run_upload(api)
        self.assertEqual(api.commands, [['publish', '--path', 'fixture.ipa']])
        self.assertIn('received this package', output)
        self.assertEqual(json.loads(output.strip().splitlines()[-1])['destination'], 'TestFlight')

    def test_publisher_error_with_a_failed_apple_upload_still_fails_with_its_codes(self):
        api = AppleFixture(uploaded=False)
        api.publisher_fails = True
        api.upload_record = 'FAILED'
        api.upload_errors = [{'code': '90062', 'description': 'not shown'}]
        with self.assertRaises(ReviewError) as caught:
            self.run_upload(api)
        self.assertIn('90062', str(caught.exception))
        self.assertNotIn('not shown', str(caught.exception))

    def test_publisher_error_with_no_apple_record_fails_after_waiting(self):
        api = AppleFixture(uploaded=False)
        api.publisher_fails = True
        sleeps = []
        with self.assertRaises(ReviewError):
            self.run_upload(api, sleeps)
        self.assertEqual(len(sleeps), 15)
        self.assertEqual(len(api.commands), 1)  # Never re-uploads on its own.

    def test_wrong_application_never_uploads(self):
        api = AppleFixture(uploaded=False)
        api.bundle = 'com.example.other'
        with self.assertRaises(ReviewError):
            self.run_upload(api)
        self.assertEqual(api.commands, [])


if __name__ == '__main__':
    unittest.main()
