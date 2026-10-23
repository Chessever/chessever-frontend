"""TestFlight uploads go to the production app once and never touch App Review."""
import io
from contextlib import redirect_stdout
import json
import unittest

from app_store_review import ReviewError
from test_app_store_review import AppleFixture
from testflight_upload import upload


class TestFlightUploadTest(unittest.TestCase):
    def run_upload(self, fixture):
        with redirect_stdout(io.StringIO()) as output:
            upload(fixture, 'fixture.ipa', '37.1.1', '3710', fixture.publisher)
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

    def test_wrong_application_never_uploads(self):
        api = AppleFixture(uploaded=False)
        api.bundle = 'com.example.other'
        with self.assertRaises(ReviewError):
            self.run_upload(api)
        self.assertEqual(api.commands, [])


if __name__ == '__main__':
    unittest.main()
