"""Upload the production IPA to TestFlight once, without any App Review step.

Reuses the shared App Store controller's identity checks, build lookup and
silent publisher, so logs carry the same selected receipt and error codes.
"""
import argparse
import json
import os
from pathlib import Path
import re

from app_store_review import AppleAPI, ReviewError, TARGETS, find_build, publish


def upload(api, package, version, number, publisher=publish):
    app, bundle, _ = TARGETS['IOS']
    application = api.get(f'/v1/apps/{app}', **{'fields[apps]': 'bundleId'})['data']
    if application['id'] != app or application['attributes']['bundleId'] != bundle:
        raise ReviewError('Unexpected production App Store application.')
    if find_build(api, app, 'IOS', version, number):
        print('This build is already uploaded; nothing to do.', flush=True)
    else:
        # A plain upload: no --app-store, no --testflight beta review. Internal
        # testers receive the build once Apple finishes processing it.
        publisher(['publish', '--path', str(package)])
        print('Package upload accepted.', flush=True)
    print(json.dumps({'app': app, 'platform': 'IOS', 'version': version,
                      'build': number, 'destination': 'TestFlight'}))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    args = parser.parse_args()
    _, bundle, branch = TARGETS['IOS']
    if os.environ.get('GITHUB_REF') != branch:
        raise ReviewError('TestFlight upload requires the production branch.')
    from codemagic.models.application_package import Ipa
    package = Ipa(args.package)
    expected = re.search(r'^version:\s*(\S+)\s*$', Path('pubspec.yaml').read_text(), re.MULTILINE)
    if package.bundle_identifier != bundle or not expected or (
            package.version + '+' + package.version_code != expected.group(1)):
        raise ReviewError('Package identity or version does not match production source.')
    upload(AppleAPI(), args.package, package.version, package.version_code)


if __name__ == '__main__':
    try:
        main()
    except (ReviewError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
