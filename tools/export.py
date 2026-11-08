#!/usr/bin/env python3
"""Build desktop review packages; verify Linux with the exported runtime and resources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from ci.common import ENGINE, ROOT, check_version, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('linux', 'windows', 'all'), default='all')
    args = parser.parse_args()
    reports = ROOT / 'build/reports/export'
    reports.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    summary = {'passed': False, 'packages': []}
    try:
        summary['engine'] = check_version(reports)
        run('import', [ENGINE, '--headless', '--path', str(ROOT), '--editor', '--import'], reports, timeout=900)
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        packages = ROOT / 'build/packages'
        packages.mkdir(parents=True, exist_ok=True)
        targets = ('linux', 'windows') if args.platform == 'all' else (args.platform,)
        for target in targets:
            directory = ROOT / 'build/exports' / target
            if directory.exists():
                shutil.rmtree(directory)
            directory.mkdir(parents=True)
            binary = directory / ('wdfz.x86_64' if target == 'linux' else 'wdfz.exe')
            run('export-' + target, [ENGINE, '--headless', '--path', str(ROOT), '--export-release', target.title(), str(binary)], reports, timeout=900)
            if not binary.is_file() or not binary.with_suffix('.pck').is_file():
                raise RuntimeError(f'{target}: exporter did not produce binary and PCK')
            if target == 'linux':
                binary.chmod(binary.stat().st_mode | 0o111)
                # Release templates do not expose --script. Check native startup, then inspect
                # the same PCK with the editor's external test runner; no tests enter the package.
                run('startup-linux', [str(binary), '--headless', '--audio-driver', 'Dummy', '--quit-after', '5'],
                    reports, timeout=180, cwd=directory)
                output = run('smoke-linux', [ENGINE, '--headless', '--audio-driver', 'Dummy',
                             '--main-pack', str(binary.with_suffix('.pck')),
                             '--script', str(ROOT / 'tools/ci/export_smoke.gd')], reports, timeout=180, cwd=directory)
                if 'EXPORT SMOKE: passed' not in output:
                    raise RuntimeError('Exported Linux runtime did not complete the smoke test')
            shutil.copy2(ROOT / 'LICENSE', directory / 'LICENSE')
            (directory / 'BUILD.json').write_text(json.dumps({'revision': revision, 'engine': summary['engine'], 'platform': target,
                'source': 'https://github.com/wd-fz/wdfz', 'runtime_verified': target == 'linux'}, indent=2) + '\n')
            (directory / 'README.txt').write_text(
                '武大附中 · 里世界 — Godot 开发验证包\n\n'
                '解压整个目录后启动 wdfz；可执行文件与 .pck 必须放在一起。\n'
                'Linux 需要 OpenGL 3.3 驱动和中文系统字体（如 Noto Sans CJK）。\n'
                '这是自动构建的移植开发版，Windows 包仅验证导出，尚未经过 Windows 真机验收。\n'
                f'源代码与许可证：https://github.com/wd-fz/wdfz/tree/{revision}\n', encoding='utf-8')
            archive = packages / f'wdfz-{target}-x86_64.zip'
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
                for path in sorted(directory.iterdir()):
                    bundle.write(path, arcname=f'wdfz-{target}/{path.name}')
            sha = hashlib.sha256()
            with archive.open('rb') as source:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    sha.update(block)
            summary['packages'].append({'file': archive.name, 'bytes': archive.stat().st_size, 'sha256': sha.hexdigest()})
            print(f'Package ready: {archive.relative_to(ROOT)}', flush=True)
        summary['passed'] = True
    finally:
        (reports / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
