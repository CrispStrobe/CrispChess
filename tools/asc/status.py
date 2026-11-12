#!/usr/bin/env python3
"""Read-only release status, including a suggested unused build number."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import client
from release_version import read_version

APP = json.loads((Path(__file__).with_name('metadata.json')).read_text())['appId']
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED'}
PENDING = {'WAITING_FOR_REVIEW', 'IN_REVIEW'}


def release_status(platform: str) -> dict:
    versions = []
    for version in client.paged(f'/v1/apps/{APP}/appStoreVersions?limit=50'):
        attrs = version['attributes']
        if attrs.get('platform') != platform:
            continue
        status, doc = client.call('GET', f"/v1/appStoreVersions/{version['id']}/build")
        if status not in (200, 404):
            raise ValueError(f'Unable to inspect attached build: HTTP {status}')
        build = doc.get('data') or {}
        versions.append({'id': version['id'], 'version': attrs['versionString'],
            'state': attrs['appStoreState'], 'buildId': build.get('id'),
            'build': build.get('attributes', {}).get('version')})
    builds = []
    path = f'/v1/builds?filter[app]={APP}&include=preReleaseVersion&sort=-uploadedDate&limit=200'
    while path:
        doc = client.expect('GET', path)
        releases = {item['id']: item['attributes'] for item in doc.get('included', [])
                    if item['type'] == 'preReleaseVersions'}
        for build in doc.get('data', []):
            release_id = build.get('relationships', {}).get('preReleaseVersion', {}).get('data', {}).get('id')
            release = releases.get(release_id)
            if release is None:
                release = client.expect('GET', f"/v1/builds/{build['id']}/preReleaseVersion")['data']['attributes']
            if release.get('platform') == platform:
                attrs = build['attributes']
                builds.append({'id': build['id'], 'build': attrs['version'],
                    'version': release['version'], 'state': attrs['processingState'],
                    'uploadedDate': attrs.get('uploadedDate')})
        path = doc.get('links', {}).get('next')
    current_version, current_build = read_version()
    editable = [v for v in versions if v['state'] in EDITABLE]
    pending = [v for v in versions if v['state'] in PENDING]
    if len(editable) > 1 or len(pending) > 1:
        raise ValueError('Ambiguous versions: more than one editable or pending release')
    if editable or pending:
        candidate = (editable or pending)[0]['version']
    elif versions:
        newest = max(versions, key=lambda v: tuple(map(int, v['version'].split('.'))))
        major, minor, patch = map(int, newest['version'].split('.'))
        candidate = f'{major}.{minor}.{patch + 1}'
    else:
        candidate = current_version
    number = max([int(current_build), *[int(b['build']) for b in builds if b['build'].isdigit()]]) + 1
    return {'appId': APP, 'platform': platform, 'versions': versions, 'builds': builds,
        'candidate': {'version': candidate, 'build': str(number)}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['IOS', 'MAC_OS'], default='MAC_OS')
    args = parser.parse_args()
    print(json.dumps(release_status(args.platform), indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
