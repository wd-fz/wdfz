import contextlib
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from ci import wait_for_ci


class ReleaseCITests(unittest.TestCase):
    revision = 'a' * 40

    def run_gate(self, skipped=None, stale=False, failed=False):
        workflows = list(wait_for_ci.REQUIRED_JOBS)

        def github(command, **_kwargs):
            if command[2] == 'list':
                workflow = command[command.index('--workflow') + 1]
                run_id = workflows.index(workflow) + 1
                return json.dumps([{'databaseId': run_id, 'headSha': 'b' * 40 if stale else self.revision,
                                    'status': 'completed', 'conclusion': 'failure' if failed and workflow == 'lan.yml' else 'success',
                                    'url': f'https://example.invalid/runs/{run_id}'}])
            workflow = workflows[int(command[3]) - 1]
            return json.dumps({'jobs': [{'name': name, 'conclusion': 'skipped' if name == skipped else 'success'}
                                       for name in wait_for_ci.REQUIRED_JOBS[workflow]]})

        with patch.dict(os.environ, {'GITHUB_SHA': self.revision, 'GITHUB_REPOSITORY': 'fixture/game'}), \
             patch.object(wait_for_ci.subprocess, 'check_output', side_effect=github), \
             patch.object(wait_for_ci.time, 'monotonic', side_effect=[0, 0, 7000]), \
             patch.object(wait_for_ci.time, 'sleep'), contextlib.redirect_stdout(io.StringIO()):
            wait_for_ci.main()

    def test_exact_source_requires_both_workflows(self):
        self.run_gate()

    def test_skipped_network_checks_do_not_satisfy_release_gate(self):
        with self.assertRaisesRegex(SystemExit, 'missing or skipped'):
            self.run_gate(skipped='LAN authority and ENet')

    def test_failed_network_workflow_blocks_release(self):
        with self.assertRaisesRegex(SystemExit, 'unsuccessful CI'):
            self.run_gate(failed=True)

    def test_success_for_another_commit_is_not_accepted(self):
        with self.assertRaisesRegex(SystemExit, 'Timed out'):
            self.run_gate(stale=True)
