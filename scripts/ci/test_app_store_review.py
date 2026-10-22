"""Exercise Apple's approved-but-held race, safe retries and publication bounds."""
import copy
import io
from contextlib import redirect_stdout
import subprocess
import unittest
from unittest.mock import patch

from app_store_review import ReviewError, submit, publish, TARGETS


def version(value='37.1.0', state='PENDING_DEVELOPER_RELEASE', build='old-build', release='MANUAL'):
    return {'id': 'version-id', 'type': 'appStoreVersions',
            'attributes': {'versionString': value, 'appStoreState': state, 'releaseType': release},
            'relationships': {'build': {'data': {'id': build, 'type': 'builds'}}}}


class AppleFixture:
    def __init__(self, previous=None, platform='IOS', uploaded=True, processing='VALID'):
        self.platform = platform
        self.rows = [copy.deepcopy(previous)] if previous else []
        self.uploaded = uploaded
        self.processing = processing
        self.requests = []
        self.commands = []
        self.bundle = TARGETS[platform][1]

    def get(self, path, **query):
        self.requests.append(('GET', path, query))
        if path == '/v1/apps/' + TARGETS[self.platform][0]:
            return {'data': {'id': TARGETS[self.platform][0], 'attributes': {'bundleId': self.bundle}}}
        if path == '/v1/builds':
            return {'data': ([{'id': 'new-build', 'attributes': {
                'version': '3710', 'expired': False, 'processingState': self.processing},
                'relationships': {'preReleaseVersion': {'data': {'id': 'release-id'}}}}]
                if self.uploaded else []),
                'included': [{'id': 'release-id', 'type': 'preReleaseVersions',
                              'attributes': {'version': '37.1.1', 'platform': self.platform}}]}
        if path.endswith('/appStoreVersions'):
            return {'data': copy.deepcopy(self.rows)}
        if path.endswith('/appStoreVersionSubmission'):
            return {'data': {'id': 'submission-id', 'type': 'appStoreVersionSubmissions'}}
        if path == '/v1/appStoreVersions/version-id':
            return {'data': copy.deepcopy(self.rows[0])}
        raise AssertionError(path)

    def request(self, method, path, body=None):
        self.requests.append((method, path, body))
        if method == 'DELETE':
            assert path == '/v1/appStoreVersionSubmissions/submission-id'
            self.rows[0]['attributes']['appStoreState'] = 'DEVELOPER_REJECTED'
        elif method == 'PATCH':
            assert path == '/v1/appStoreVersions/version-id'
            self.rows[0]['attributes'].update(body['data']['attributes'])
        else:
            raise AssertionError((method, path))
        return {}

    def publisher(self, args):
        self.commands.append(args)
        if '--app-store' not in args:
            self.uploaded = True
            return
        assert '--skip-package-upload' in args
        assert args[args.index('--release-type') + 1] == 'MANUAL'
        if not self.rows:
            self.rows = [version('37.1.1', 'PREPARE_FOR_SUBMISSION')]
        self.rows[0]['attributes'].update(appStoreState='WAITING_FOR_REVIEW', releaseType='MANUAL')
        self.rows[0]['relationships']['build']['data']['id'] = 'new-build'


class AppReviewFlowTest(unittest.TestCase):
    def run_flow(self, fixture, replace=False):
        with redirect_stdout(io.StringIO()) as output:
            submit(fixture, fixture.platform, 'fixture.ipa', '37.1.1', '3710', 'notes.txt',
                   replace, fixture.publisher, lambda _: self.fail('Unexpected processing wait'))
        return output.getvalue()

    def test_approved_manual_version_is_withdrawn_and_renamed_without_release(self):
        api = AppleFixture(version())
        receipt = self.run_flow(api, replace=True)
        writes = [(method, path, body) for method, path, body in api.requests if method != 'GET']
        self.assertEqual([row[0] for row in writes], ['DELETE', 'PATCH'])
        self.assertEqual(writes[1][2]['data']['attributes'],
                         {'versionString': '37.1.1', 'releaseType': 'MANUAL'})
        self.assertEqual(len(api.commands), 1)  # Already uploaded; no duplicate delivery.
        self.assertIn('WAITING_FOR_REVIEW', receipt)
        self.assertTrue(all('ReleaseRequests' not in path for _, path, _ in api.requests))

    def test_pending_or_approved_replacement_is_never_implicit(self):
        for state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE'):
            api = AppleFixture(version(state=state))
            with self.subTest(state=state), self.assertRaisesRegex(ReviewError, 'explicit replacement'):
                self.run_flow(api)
            self.assertFalse(api.commands)
            self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))

    def test_new_binary_uploads_once_then_submits_without_reupload(self):
        api = AppleFixture(uploaded=False)
        self.run_flow(api)
        self.assertEqual(len(api.commands), 2)
        self.assertNotIn('--app-store', api.commands[0])
        self.assertIn('--skip-package-upload', api.commands[1])

    def test_invalid_new_binary_preserves_the_existing_approval(self):
        api = AppleFixture(version(), processing='INVALID')
        with self.assertRaisesRegex(ReviewError, 'invalid'):
            self.run_flow(api, replace=True)
        self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))
        self.assertFalse(api.commands)

    def test_repeat_of_successful_review_does_not_cancel_or_resubmit_it(self):
        for state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE'):
            api = AppleFixture(version('37.1.1', state, 'new-build'))
            self.run_flow(api, replace=True)
            self.assertFalse(api.commands)
            self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))

    def test_newer_versions_and_missing_manual_holds_are_preserved(self):
        for old in (version('38.0.0'), version(release='AFTER_APPROVAL')):
            api = AppleFixture(old)
            with self.assertRaises(ReviewError):
                self.run_flow(api, replace=True)
            self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))

    def test_wrong_application_never_uploads_or_changes_review(self):
        api = AppleFixture(version())
        api.bundle = 'com.someone.else'
        with self.assertRaisesRegex(ReviewError, 'Unexpected production'):
            self.run_flow(api, replace=True)
        self.assertFalse(api.commands)

    def test_published_target_version_is_never_resubmitted(self):
        api = AppleFixture(version('37.1.1', 'READY_FOR_SALE', 'new-build'))
        with self.assertRaisesRegex(ReviewError, 'not editable'):
            self.run_flow(api, replace=True)
        self.assertFalse(api.commands)
        self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))

    def test_processing_timeout_preserves_the_old_approved_version(self):
        api = AppleFixture(version(), processing='PROCESSING')
        with redirect_stdout(io.StringIO()), self.assertRaisesRegex(ReviewError, 'timed out'):
            submit(api, 'IOS', 'fixture.ipa', '37.1.1', '3710', 'notes.txt', True,
                   api.publisher, lambda _: None)
        self.assertFalse(api.commands)
        self.assertTrue(all(method == 'GET' for method, _, _ in api.requests))

    def test_mac_uses_its_separate_app_and_same_manual_review_contract(self):
        api = AppleFixture(platform='MAC_OS')
        receipt = self.run_flow(api)
        self.assertIn('6824524785', receipt)
        self.assertEqual(api.commands[0][api.commands[0].index('--platform') + 1], 'MAC_OS')

    def test_publisher_never_prints_private_resource_summaries(self):
        private = 'https://private.example/subscription/callback-token'
        result = subprocess.CompletedProcess([], 1, private, 'returned 409: secret\nITMS-90000')
        with patch('app_store_review.subprocess.run', return_value=result) as run:
            with self.assertRaises(ReviewError) as error:
                publish(['publish', '--path', 'fixture.ipa'])
        self.assertNotIn(private, str(error.exception))
        self.assertIn('returned 409', str(error.exception))
        self.assertIn('ITMS-90000', str(error.exception))
        self.assertTrue(run.call_args.kwargs['capture_output'])
        self.assertIn('--silent', run.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
