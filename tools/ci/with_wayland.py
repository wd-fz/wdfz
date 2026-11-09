#!/usr/bin/env python3
"""Run with native Wayland and a virtual pointer seat; the compositor uses Xvfb, not XWayland."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    if len(sys.argv) < 2:
        raise SystemExit('Usage: python tools/ci/with_wayland.py COMMAND [ARG ...]')
    reports = Path('build/reports/wayland')
    reports.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='wdfz-wayland-') as runtime:
        env = {**os.environ, 'XDG_RUNTIME_DIR': runtime, 'WAYLAND_DISPLAY': 'wdfz-test'}
        with (reports / 'weston.log').open('w') as log:
            # The headless backend has no pointer seat: Godot 4.6 cannot lock its
            # mouse there. An X11 parent gives Weston real input while the game
            # still connects exclusively through the native Wayland protocol.
            compositor = subprocess.Popen([os.environ.get('WESTON_BIN', 'weston'),
                '--backend=x11-backend.so', '--use-pixman', '--shell=desktop-shell.so',
                '--socket=wdfz-test', '--idle-time=0', '--width=1280', '--height=720', '--no-config'],
                env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while not (Path(runtime) / 'wdfz-test').is_socket():
                    if compositor.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError('Native Wayland compositor failed; see build/reports/wayland/weston.log')
                    time.sleep(.1)
                return subprocess.call(sys.argv[1:], env=env)
            finally:
                compositor.terminate()
                try:
                    compositor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    compositor.kill()
                    compositor.wait()


if __name__ == '__main__':
    sys.exit(main())
