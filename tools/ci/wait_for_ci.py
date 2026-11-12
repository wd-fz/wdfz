#!/usr/bin/env python3
"""Require the push CI for the exact release commit; never accept skipped or stale checks."""
import json
import os
import subprocess
import time


def main():
    revision = os.environ['GITHUB_SHA']
    repo = os.environ['GITHUB_REPOSITORY']
    deadline = time.monotonic() + 115 * 60
    previous = None
    while time.monotonic() < deadline:
        output = subprocess.check_output(['gh', 'run', 'list', '--repo', repo,
            '--workflow', 'godot.yml', '--commit', revision, '--event', 'push',
            '--json', 'databaseId,headSha,status,conclusion,url', '--limit', '10'], text=True)
        runs = [run for run in json.loads(output) if run['headSha'] == revision]
        run = runs[0] if runs else None
        state = (run['databaseId'], run['status'], run['conclusion']) if run else None
        if state != previous:
            print(run or 'Waiting for push CI to appear', flush=True)
            previous = state
        if run and run['status'] == 'completed':
            if run['conclusion'] != 'success':
                raise SystemExit('Release blocked by unsuccessful CI: ' + run['url'])
            jobs = json.loads(subprocess.check_output(['gh', 'run', 'view', str(run['databaseId']),
                '--repo', repo, '--json', 'jobs'], text=True))['jobs']
            required = {'Structure and tooling', 'Regression (headless)', 'Regression (windowed)',
                        'Regression (Vulkan Mobile)', 'Desktop builds'}
            passed = {job['name'] for job in jobs if job['conclusion'] == 'success'}
            if not required <= passed:
                raise SystemExit('Required CI jobs missing or skipped: ' + str(required - passed))
            print('Verified full CI for ' + revision, flush=True)
            return
        time.sleep(20)
    raise SystemExit('Timed out waiting for exact-commit CI; release remains unpublished')


if __name__ == '__main__':
    main()
