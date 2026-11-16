#!/usr/bin/env python3
"""Run the Android local-network selection/ownership logic on a Java 17+ runtime."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java', default=shutil.which('java'))
    args = parser.parse_args()
    if not args.java:
        raise RuntimeError('Java 17+ with jdk.compiler is required')
    output = ROOT / 'build/reports/android-network/classes'
    output.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'platform/android/lan/src/org/wdfz/lan/LocalNetworkRoute.java'
    test = ROOT / 'tests/android/LocalNetworkRouteTest.java'
    subprocess.run([args.java, '--module', 'jdk.compiler/com.sun.tools.javac.Main', '-source', '17', '-target', '17',
                    '-encoding', 'UTF-8', '-d', str(output), str(source), str(test)], check=True, timeout=60)
    subprocess.run([args.java, '-cp', str(output), 'org.wdfz.lan.LocalNetworkRouteTest'], check=True, timeout=30)


if __name__ == '__main__':
    main()
