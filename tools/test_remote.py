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
    parser.add_argument('--players', type=int, choices=(2, 4), default=2)
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
            if executables and (scratch / 'bootstrap.json').exists() and os.access(executables[0], os.X_OK): break
            time.sleep(.1)
        if not executables: raise RuntimeError('Official launcher did not unpack EasyTier')
        easytier = scratch / 'easytier-core'
        shutil.copy2(executables[0], easytier)
        easytier.chmod(0o755)
        bootstrap.terminate()
        bootstrap.wait(timeout=5)
        relay_port, game_port = free_port(), free_port()
        launch([str(easytier), '--network-name', 'wdfz-test-rendezvous', '--listeners', f'tcp://127.0.0.1:{relay_port}',
                '--rpc-portal', '0', '--no-tun'], 'rendezvous', os.environ.copy())
        command = [ENGINE, '--headless', '--path', str(ROOT), '--script', 'res://tests/network/remote_peer.gd', '--',
                   f'--directory={scratch}', f'--port={game_port}', f'--relay={relay_port}', f'--players={args.players}']
        host = launch(command + ['--host'], 'host', environment('host'))
        deadline = time.monotonic() + 130
        while not (scratch / 'invitation.json').exists():
            if host.poll() is not None or time.monotonic() > deadline: raise RuntimeError('Remote host failed; inspect host.log')
            time.sleep(.1)
        guests = [launch(command + [f'--name=guest-{index}'], f'guest-{index}', environment(f'guest-{index}')) for index in range(1, args.players)]
        peers = [host, *guests]
        deadline = time.monotonic() + 180
        while any(peer.poll() is None for peer in peers):
            if any(p.poll() not in (None, 0) for p in peers) or time.monotonic() > deadline:
                raise RuntimeError('Remote peer failed or timed out; inspect host/guest.log')
            time.sleep(.2)
        summaries = [json.loads((scratch / (name + '-summary.json')).read_text()) for name in ['host', *[f'guest-{i}' for i in range(1, args.players)]]]
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
