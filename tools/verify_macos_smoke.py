#!/usr/bin/env python3
"""Reject a Mac launch that merely keeps a process alive after a Dart failure."""
import argparse
from pathlib import Path
import re

FRAME_MARKER = 'CrispChess first frame rendered'
ENGINE_MARKER = 'Engine state: EngineState.ready'
FAILURE = re.compile(r'Unhandled Exception|uncaught exception|EXC_(?:CRASH|BAD_ACCESS)|Fatal error:|Code Signature Invalid', re.IGNORECASE)


def verify_log(path: Path) -> None:
    text = path.read_text(errors='replace')
    failure = FAILURE.search(text)
    if failure:
        raise ValueError(f'{path}: runtime failure: {failure.group()}')
    if FRAME_MARKER not in text:
        raise ValueError(f'{path}: Flutter did not render its first frame')
    if ENGINE_MARKER not in text:
        raise ValueError(f'{path}: built-in opponent did not become ready')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    try:
        verify_log(args.log)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Mac launch check failed: {error}\n')
    print(f'Verified Flutter frame, ready engine and clean launch: {args.log}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
