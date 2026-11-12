#!/usr/bin/env python3
"""Real official Terracotta / EasyTier / ENet test with a local rendezvous node (no NAT claim)."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import time
from ci.common import ENGINE, ROOT, run
import terracotta


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unit', action='store_true')
    args = parser.parse_args()
    reports = ROOT / 'build/reports/remote'
    reports.mkdir(parents=True, exist_ok=True)
    if args.unit:
        text = run('unit', [ENGINE, '--headless', '--path', str(ROOT), '--script', 'res://tests/network/terracotta.gd'], reports)
        if 'failures' not in text or 'checks, 0 failures' not in text: raise RuntimeError('Missing remote test summary')
        print(text.strip())
        return
    binary = terracotta.prepare('linux')
    scratch = reports / 'private-fixture'
    if scratch.exists(): shutil.rmtree(scratch)
    scratch.mkdir()
    processes, logs = [], []
    try:
        def launch(command, label, env):
            log = (reports / (label + '.log')).open('w')
            logs.append(log)
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, env=env, start_new_session=True)
            processes.append(process)
            return process

        def environment(label):
            directory = scratch / label
            directory.mkdir()
            # Loopback fixture only: EasyTier normally binds outbound sockets to a
            # physical interface, which cannot reach a loopback rendezvous server.
            return {**os.environ, 'TMPDIR': str(directory), 'XDG_DATA_HOME': str(directory), 'ET_BIND_DEVICE': 'false'}

        # Extract the embedded, already checksum-verified EasyTier through its official launcher.
        bootstrap = launch([str(binary), '--hmcl', str(scratch / 'bootstrap.json')], 'bootstrap', environment('bootstrap'))
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            executables = list((scratch / 'bootstrap').rglob('easytier-core'))
            if executables: break
            time.sleep(.1)
        if not executables: raise RuntimeError('Official launcher did not unpack EasyTier')
        easytier = scratch / 'easytier-core'
        shutil.copy2(executables[0], easytier)
        bootstrap.terminate()
        bootstrap.wait(timeout=5)
        relay_port, game_port = free_port(), free_port()
        launch([str(easytier), '--network-name', 'wdfz-test-rendezvous', '--listeners', f'tcp://127.0.0.1:{relay_port}',
                '--rpc-portal', '0', '--no-tun'], 'rendezvous', os.environ.copy())
        command = [ENGINE, '--headless', '--path', str(ROOT), '--script', 'res://tests/network/remote_peer.gd', '--',
                   f'--directory={scratch}', f'--port={game_port}', f'--relay={relay_port}']
        host = launch(command + ['--host'], 'host', environment('host'))
        deadline = time.monotonic() + 130
        while not (scratch / 'invitation.json').exists():
            if host.poll() is not None or time.monotonic() > deadline: raise RuntimeError('Remote host failed; inspect host.log')
            time.sleep(.1)
        guest = launch(command, 'guest', environment('guest'))
        deadline = time.monotonic() + 180
        while host.poll() is None or guest.poll() is None:
            if any(p.poll() not in (None, 0) for p in (host, guest)) or time.monotonic() > deadline:
                raise RuntimeError('Remote peer failed or timed out; inspect host/guest.log')
            time.sleep(.2)
        summaries = [json.loads((scratch / (name + '-summary.json')).read_text()) for name in ('host', 'guest')]
        if any(s['failures'] or s['checks'] < 3 for s in summaries): raise RuntimeError('Remote assertions failed')
        (reports / 'summary.json').write_text(json.dumps({'passed': True, 'transport': 'official Terracotta 0.4.2 / EasyTier / ENet',
            'rendezvous': 'local fixture; does not verify internet NAT traversal', 'peers': summaries}, indent=2) + '\n')
        print('TERRACOTTA INTEGRATION: real tunnel, UDP gameplay, reconnect and cleanup passed', flush=True)
    finally:
        for process in reversed(processes):
            # Only our isolated test process groups, including their native children.
            try: os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            if process.poll() is None:
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
        # Do not publish room codes, addresses or upstream logs from this private directory.
        for log in logs: log.close()


if __name__ == '__main__': main()
