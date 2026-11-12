#!/usr/bin/env python3
"""Create and submit a new macOS version after its checked build is valid."""
from __future__ import annotations
import argparse
from pathlib import Path
import time
import client
import status
import store
import review_notes
import submit
from replace_build import APP, EDITABLE, PENDING, invoke
from release_version import read_version


def release(build: str, expected_previous: str, notes_file: Path, *, attempts=60, interval=15):
    version, source_build = read_version()
    if build != source_build or not notes_file.read_text().strip():
        raise ValueError('Expected source build and nonempty review note')
    for attempt in range(attempts):
        snapshot = status.release_status('MAC_OS')
        numbered = [b for b in snapshot['builds'] if b['build'] == build]
        if any(b['version'] != version for b in numbered):
            raise ValueError('Build number belongs to another marketing version')
        matches = numbered
        if any(b['state'] in ('INVALID', 'FAILED') for b in matches):
            raise ValueError('Build failed processing')
        valid = [b for b in matches if b['state'] == 'VALID']
        if len(valid) > 1:
            raise ValueError('Ambiguous build')
        if valid:
            break
        if attempt + 1 < attempts:
            time.sleep(interval)
    else:
        raise ValueError('Build did not finish processing; nothing was changed')
    versions = snapshot['versions']
    target = [v for v in versions if v['version'] == version]
    if len(target) > 1:
        raise ValueError('Ambiguous target version')
    if target and target[0]['state'] in PENDING and target[0]['build'] == build:
        print(f'macOS {version} ({build}) already submitted')
        return
    previous = [v for v in versions if v['state'] == 'READY_FOR_SALE' and v['build'] == expected_previous]
    if len(previous) != 1 or tuple(map(int, previous[0]['version'].split('.'))) >= tuple(map(int, version.split('.'))):
        raise ValueError('Expected previous approved release changed')
    if any(tuple(map(int, v['version'].split('.'))) > tuple(map(int, version.split('.'))) for v in versions):
        raise ValueError('A newer macOS version already exists')
    if any(v['state'] in EDITABLE | PENDING and v['version'] != version for v in versions):
        raise ValueError('Another macOS version is in progress')
    if target and (target[0]['state'] not in EDITABLE or target[0]['build'] not in (None, build)):
        raise ValueError('Target version is not editable or carries another build')
    submissions = client.paged(f'/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=MAC_OS&limit=20')
    if any(s['attributes'].get('state') in ('UNRESOLVED_ISSUES', 'READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW') for s in submissions):
        raise ValueError('Another review submission exists; refusing to alter it')
    if not target:
        client.expect('POST', '/v1/appStoreVersions', {'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': 'MAC_OS', 'versionString': version},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})
    invoke(store, ['--build', build, '--platform', 'MAC_OS', '--attach-only'])
    invoke(review_notes, ['--build', build, '--platform', 'MAC_OS', '--notes-file', str(notes_file)])
    invoke(submit, ['--build', build, '--platform', 'MAC_OS', '--dry-run'])
    invoke(submit, ['--build', build, '--platform', 'MAC_OS'])
    print(f'macOS {version} ({build}) submitted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True)
    parser.add_argument('--expected-previous', required=True)
    parser.add_argument('--notes-file', type=Path, required=True)
    args = parser.parse_args()
    release(args.build, args.expected_previous, args.notes_file)


if __name__ == '__main__':
    main()
