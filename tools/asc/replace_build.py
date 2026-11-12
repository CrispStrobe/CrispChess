#!/usr/bin/env python3
"""Replace a pending Mac build only after a checked replacement is processed.

The release workflow calls this after native validation and package upload.
The expected old build prevents withdrawing a submission changed by someone else.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
import time

import client
import store
import review_notes
import submit
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from release_version import read_version

APP = json.loads(Path(__file__).with_name('metadata.json').read_text())['appId']
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED'}
PENDING = {'WAITING_FOR_REVIEW', 'IN_REVIEW'}


def invoke(module, args):
    previous = sys.argv
    try:
        sys.argv = [module.__file__, *args]
        return module.main()
    finally:
        sys.argv = previous


def replace(build: str, expected_build: str, notes_file: Path, *, attempts=60, interval=15) -> None:
    version_name, source_build = read_version()
    if build != source_build:
        raise ValueError('Replacement build does not match pubspec.yaml')
    if not notes_file.read_text().strip():
        raise ValueError('Review notes are required')
    # No current submission is changed until the exact replacement is VALID.
    for attempt in range(attempts):
        valid = []
        for item in client.paged(f'/v1/apps/{APP}/builds?limit=200'):
            attrs = item['attributes']
            if attrs.get('version') != build:
                continue
            release = client.expect('GET', f"/v1/builds/{item['id']}/preReleaseVersion")['data']['attributes']
            if release.get('platform') != 'MAC_OS':
                continue
            if release.get('version') != version_name:
                raise ValueError('Replacement marketing version does not match source')
            state = attrs.get('processingState')
            if state in ('FAILED', 'INVALID'):
                raise ValueError('Replacement failed App Store processing')
            if state == 'VALID':
                valid.append(item)
        if len(valid) == 1:
            break
        if len(valid) > 1:
            raise ValueError('Ambiguous replacement builds')
        if attempt + 1 < attempts:
            print('Waiting for replacement build processing', flush=True)
            time.sleep(interval)
    else:
        raise ValueError('Replacement did not finish processing; current submission retained')

    versions = [v for v in client.paged(f'/v1/apps/{APP}/appStoreVersions?limit=50')
                if v['attributes'].get('platform') == 'MAC_OS'
                and v['attributes'].get('versionString') == version_name]
    if len(versions) != 1:
        raise ValueError('Expected exactly one matching macOS release')
    version = versions[0]
    version_id = version['id']
    attached = client.expect('GET', f'/v1/appStoreVersions/{version_id}/build')['data']['attributes']['version']
    state = version['attributes']['appStoreState']
    if attached == build and state in PENDING:
        print(f'macOS {version_name} ({build}) is already submitted')
        return
    if attached not in (expected_build, build):
        raise ValueError('Attached build changed; refusing to withdraw it')
    if state not in EDITABLE | PENDING:
        raise ValueError(f'Release is now {state}; current submission retained')
    if state in PENDING:
        submissions = [s for s in client.paged(
            f'/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=MAC_OS&limit=20')
            if s['attributes'].get('state') in PENDING]
        matches = []
        for submission in submissions:
            items = client.paged(f"/v1/reviewSubmissions/{submission['id']}/items?include=appStoreVersion&limit=20")
            linked = [item.get('relationships', {}).get('appStoreVersion', {}).get('data') for item in items]
            if any(item and item.get('id') == version_id for item in linked):
                if len(items) != 1:
                    raise ValueError('Submission contains other items; refusing to cancel them')
                matches.append(submission)
        if len(matches) != 1:
            raise ValueError('Expected one pending submission for the current version')
        submission_id = matches[0]['id']
        client.expect('PATCH', f'/v1/reviewSubmissions/{submission_id}', {'data': {
            'type': 'reviewSubmissions', 'id': submission_id, 'attributes': {'canceled': True}}})
        for attempt in range(attempts):
            current = client.expect('GET', f'/v1/appStoreVersions/{version_id}')['data']
            submission = client.expect('GET', f'/v1/reviewSubmissions/{submission_id}')['data']
            if (current['attributes']['appStoreState'] in EDITABLE
                    and submission['attributes']['state'] == 'COMPLETE'):
                break
            if attempt + 1 < attempts:
                time.sleep(interval)
        else:
            raise ValueError('Apple is still processing the withdrawal; retry when editable')
    current = client.expect('GET', f'/v1/appStoreVersions/{version_id}')['data']['attributes']
    current_build = client.expect('GET', f'/v1/appStoreVersions/{version_id}/build')['data']['attributes']['version']
    if current.get('versionString') != version_name or current_build not in (expected_build, build):
        raise ValueError('Release changed during preparation; refusing to overwrite it')
    invoke(store, ['--build', build, '--platform', 'MAC_OS', '--attach-only'])
    invoke(review_notes, ['--build', build, '--platform', 'MAC_OS', '--notes-file', str(notes_file)])
    invoke(submit, ['--build', build, '--platform', 'MAC_OS', '--dry-run'])
    invoke(submit, ['--build', build, '--platform', 'MAC_OS'])
    print(f'Replacement macOS {version_name} ({build}) submitted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True)
    parser.add_argument('--expected-build', required=True)
    parser.add_argument('--notes-file', type=Path, required=True)
    args = parser.parse_args()
    replace(args.build, args.expected_build, args.notes_file)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
