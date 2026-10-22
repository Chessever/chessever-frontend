"""Upload once, replace only explicitly, and verify a MANUAL App Review hold.

Shared verbatim with the desktop repository. Publisher output stays private:
its resource summaries include subscription callback URLs and review details.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

TARGETS = {
    'IOS': ('6752567269', 'com.chessever.app', 'refs/heads/stable'),
    'MAC_OS': ('6824524785', 'com.chessever.desktop', 'refs/heads/main'),
}
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED',
            'METADATA_REJECTED', 'INVALID_BINARY', 'READY_FOR_REVIEW'}
WITHDRAWABLE = {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE',
                'WAITING_FOR_EXPORT_COMPLIANCE'}
REVIEWED = {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_DEVELOPER_RELEASE'}


class ReviewError(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


class AppleAPI:
    """Only this fixed HTTPS origin receives the short-lived signing token."""
    def __init__(self):
        self.token = ''
        self.expires = 0
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, path, body=None):
        import jwt  # Installed by the hash-locked release-tools requirements.
        if not path.startswith('/v1/') or '://' in path:
            raise ReviewError('Unexpected App Store API path.')
        if time.time() >= self.expires:
            names = ('APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_KEY_IDENTIFIER',
                     'APP_STORE_CONNECT_PRIVATE_KEY')
            if any(not os.environ.get(name) for name in names):
                raise ReviewError('App Store signing configuration is incomplete.')
            self.expires = int(time.time()) + 600
            self.token = jwt.encode(
                {'iss': os.environ[names[0]], 'iat': self.expires - 600,
                 'exp': self.expires, 'aud': 'appstoreconnect-v1'},
                os.environ[names[2]], algorithm='ES256',
                headers={'kid': os.environ[names[1]], 'typ': 'JWT'},
            )
        request = urllib.request.Request(
            'https://api.appstoreconnect.apple.com' + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={'Authorization': 'Bearer ' + self.token,
                     'Content-Type': 'application/json'}, method=method,
        )
        try:
            with self.opener.open(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            # Do not echo response bodies or private resource metadata.
            raise ReviewError(f'App Store API {method} failed (HTTP {error.code}).') from None
        except urllib.error.URLError:
            raise ReviewError('App Store API connection failed.') from None

    def get(self, path, **query):
        if query:
            path += '?' + urllib.parse.urlencode(query)
        return self.request('GET', path)


def state(version):
    attrs = version['attributes']
    return attrs.get('appVersionState') or attrs.get('appStoreState')


def version_number(value):
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
        raise ReviewError('Unexpected marketing version.')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def find_build(api, app, platform, version, number):
    response = api.get('/v1/builds', **{
        'filter[app]': app, 'filter[version]': number, 'include': 'preReleaseVersion',
        'fields[builds]': 'version,processingState,expired,preReleaseVersion',
        'fields[preReleaseVersions]': 'version,platform', 'limit': 200,
    })
    if response.get('links', {}).get('next'):
        raise ReviewError('Build lookup requires further inspection.')
    releases = {row['id']: row['attributes'] for row in response.get('included', [])
                if row['type'] == 'preReleaseVersions'}
    matches = []
    for build in response['data']:
        ref = build['relationships']['preReleaseVersion']['data']['id']
        release = releases.get(ref, {})
        if release.get('version') == version and release.get('platform') == platform:
            matches.append(build)
    if len(matches) > 1:
        raise ReviewError('Ambiguous uploaded build.')
    return matches[0] if matches else None


def wait_build(api, app, platform, version, number, sleep):
    for attempt in range(121):
        build = find_build(api, app, platform, version, number)
        if build:
            attrs = build['attributes']
            if attrs.get('expired') or attrs['processingState'] not in {'PROCESSING', 'VALID'}:
                raise ReviewError('Uploaded build is expired or invalid; review was preserved.')
            if attrs['processingState'] == 'VALID':
                return build
        if attempt == 120:
            raise ReviewError('Build processing timed out; review was preserved.')
        if attempt % 10 == 0:
            print('Waiting for the uploaded build to become VALID.', flush=True)
        sleep(30)


def versions(api, app, platform):
    response = api.get(f'/v1/apps/{app}/appStoreVersions', **{
        'filter[platform]': platform, 'include': 'build', 'limit': 200,
        'fields[appStoreVersions]': 'versionString,appStoreState,appVersionState,releaseType,build',
        'fields[builds]': 'version',
    })
    if response.get('links', {}).get('next'):
        raise ReviewError('Version lookup requires further inspection.')
    return response['data']


def attached_build(version):
    return (version.get('relationships', {}).get('build', {}).get('data') or {}).get('id')


def prepare_version(api, app, platform, version, build, replace, sleep):
    rows = versions(api, app, platform)
    target = next((row for row in rows if row['attributes']['versionString'] == version), None)
    if target and state(target) in REVIEWED and attached_build(target) == build['id']:
        if target['attributes'].get('releaseType') != 'MANUAL':
            raise ReviewError('Existing review does not have a MANUAL release hold.')
        return True  # An upload/review retry must not cancel its own completed work.
    blockers = [row for row in rows if state(row) in EDITABLE | WITHDRAWABLE]
    if len(blockers) > 1:
        raise ReviewError('Multiple outstanding versions require inspection.')
    if target and state(target) in EDITABLE:
        return False
    if not blockers:
        if target:
            raise ReviewError('The target version is not editable.')
        return False
    previous = blockers[0]
    if not replace:
        raise ReviewError('An unreleased version exists; explicit replacement is required.')
    if version_number(previous['attributes']['versionString']) > version_number(version):
        raise ReviewError('Refusing to replace a newer version.')
    if previous['attributes'].get('releaseType') != 'MANUAL':
        raise ReviewError('Refusing to replace a version without a MANUAL hold.')
    identifier = previous['id']
    if state(previous) in WITHDRAWABLE:
        # The publisher only cancels active reviews. Apple's approved, held
        # version requires this version-specific withdrawal before it is editable.
        submission = api.get(f'/v1/appStoreVersions/{identifier}/appStoreVersionSubmission')['data']
        if not submission or submission.get('type') != 'appStoreVersionSubmissions':
            raise ReviewError('Cannot identify the previous version submission.')
        api.request('DELETE', '/v1/appStoreVersionSubmissions/' + submission['id'])
        for attempt in range(61):
            previous = api.get(f'/v1/appStoreVersions/{identifier}')['data']
            if state(previous) in EDITABLE:
                break
            if attempt == 60:
                raise ReviewError('Version withdrawal is still processing.')
            sleep(2)
    # Keep screenshots, localizations and review details in the existing slot.
    # Creating a second outstanding version produces Apple's 409 response.
    api.request('PATCH', f'/v1/appStoreVersions/{identifier}', {'data': {
        'type': 'appStoreVersions', 'id': identifier,
        'attributes': {'versionString': version, 'releaseType': 'MANUAL'},
    }})
    print('Prepared the explicitly replaced version; release remains MANUAL.', flush=True)
    return False


def publish(args):
    result = subprocess.run(['app-store-connect', *args, '--silent', '--disable-jwt-cache'],
                            capture_output=True, text=True)
    if result.returncode:
        # Even unexpected direct stdout from the CLI cannot expose callback URLs,
        # demo-account fields or token values. Only machine error codes are public.
        codes = sorted(set(re.findall(r'ITMS-\d+|returned \d{3}', result.stdout + result.stderr)))
        raise ReviewError('App Store publisher failed; diagnostic codes: ' + ', '.join(codes))


def submit(api, platform, package, version, number, notes, replace=False,
           publisher=publish, sleep=time.sleep):
    app, bundle, _ = TARGETS[platform]
    application = api.get(f'/v1/apps/{app}', **{'fields[apps]': 'bundleId'})['data']
    if application['id'] != app or application['attributes']['bundleId'] != bundle:
        raise ReviewError('Unexpected production App Store application.')
    if not find_build(api, app, platform, version, number):
        publisher(['publish', '--path', str(package)])
        print('Package upload accepted.', flush=True)
    build = wait_build(api, app, platform, version, number, sleep)
    already_reviewed = prepare_version(api, app, platform, version, build, replace, sleep)
    if not already_reviewed:
        publisher(['publish', '--path', str(package), '--skip-package-upload', '--app-store',
                   '--platform', platform, '--release-type', 'MANUAL', '--whats-new', '@file:' + str(notes),
                   '--max-find-build-wait', '30', '--max-build-processing-wait', '60'])
    for attempt in range(61):
        target = next((row for row in versions(api, app, platform)
                       if row['attributes']['versionString'] == version), None)
        if target and target['attributes'].get('releaseType') != 'MANUAL':
            raise ReviewError('Submission does not have a MANUAL release hold.')
        if target and state(target) in REVIEWED and attached_build(target) == build['id']:
            print(json.dumps({'app': app, 'platform': platform, 'version': version,
                              'build': number, 'state': state(target), 'releaseType': 'MANUAL'}))
            return
        if attempt == 60:
            raise ReviewError('Could not verify review submission and attached build.')
        sleep(2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=TARGETS, required=True)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--release-type', choices=['MANUAL'], required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--replace-pending', choices=['true', 'false'], default='false')
    args = parser.parse_args()
    _, bundle, branch = TARGETS[args.platform]
    if (os.environ.get('GITHUB_REF') or os.environ.get('RELEASE_REF')) != branch:
        raise ReviewError('Review submission requires the production branch.')
    from codemagic.models.application_package import Ipa, MacOsPackage
    package = (Ipa if args.platform == 'IOS' else MacOsPackage)(args.package)
    expected = re.search(r'^version:\s*(\S+)\s*$', Path('pubspec.yaml').read_text(), re.MULTILINE)
    if package.bundle_identifier != bundle or not expected or (
            package.version + '+' + package.version_code != expected.group(1)):
        raise ReviewError('Package identity or version does not match production source.')
    submit(AppleAPI(), args.platform, args.package, package.version, package.version_code,
           args.notes, args.replace_pending == 'true')


if __name__ == '__main__':
    try:
        main()
    except (ReviewError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
