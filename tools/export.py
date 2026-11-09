#!/usr/bin/env python3
"""Build desktop packages and verify Linux on both native Wayland and X11."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile
from ci.common import ENGINE, ROOT, check_version, run
from ci import quality
from export_android import RELEASE_VERSION


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=('linux', 'windows', 'all'), default='all')
    parser.add_argument('--release', action='store_true', help='versioned formal release assets; requires a clean tree')
    args = parser.parse_args()
    reports = ROOT / 'build/reports/export'
    reports.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    summary = {'passed': False, 'packages': []}
    try:
        print(quality.check(ROOT), flush=True)
        summary['engine'] = check_version(reports)
        run('import', [ENGINE, '--headless', '--path', str(ROOT), '--editor', '--import'], reports, timeout=900)
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())
        if args.release and dirty:
            raise ValueError('Formal packages require a clean source tree')
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
                for display in ('x11', 'wayland'):
                    # No display/window flag for Wayland: exercise the actual shipping defaults.
                    flags = ['--display-driver', 'x11'] if display == 'x11' else []
                    with tempfile.TemporaryDirectory(prefix='wdfz-export-profile-') as profile:
                        env = {**os.environ, 'XDG_DATA_HOME': profile}
                        output = run('startup-linux-' + display, [str(binary), *flags, '--audio-driver', 'Dummy', '--verbose',
                                     '--', '--startup-smoke', '--expect-display=' + display, '--expect-windowed'],
                                     reports, timeout=180, cwd=directory, env=env)
                        if ('STARTUP SMOKE: passed' not in output or f'STARTUP DISPLAY: {display}' not in output
                                or 'Vulkan' not in output or 'Forward+' not in output):
                            raise RuntimeError(f'Exported Linux runtime did not start windowed with Vulkan on {display}')
                        output = run('smoke-linux-' + display, [ENGINE, *flags, '--audio-driver', 'Dummy',
                                     '--main-pack', str(binary.with_suffix('.pck')),
                                     '--script', str(ROOT / 'tools/ci/export_smoke.gd')], reports, timeout=180, cwd=directory, env=env)
                        if 'EXPORT SMOKE: passed' not in output or 'EXPORT RENDERER: vulkan / forward_plus' not in output:
                            raise RuntimeError(f'Exported Linux runtime did not complete the {display} smoke test')
            shutil.copy2(ROOT / 'LICENSE', directory / 'LICENSE')
            info = {'revision': revision, 'engine': summary['engine'], 'platform': target,
                    'version': RELEASE_VERSION, 'release': args.release, 'working_tree_dirty': dirty,
                    'source': 'https://github.com/wd-fz/wdfz', 'runtime_verified': target == 'linux',
                    'rendering_driver': 'vulkan', 'rendering_method': 'forward_plus',
                    'rendering_verified': target == 'linux', 'window_default': 'windowed',
                    'display_drivers_verified': ['x11', 'wayland'] if target == 'linux' else []}
            (directory / 'BUILD.json').write_text(json.dumps(info, indent=2) + '\n')
            (directory / 'README.txt').write_text(
                f'武大附中 · 里世界 — v{RELEASE_VERSION}\n\n'
                '解压整个目录后启动 wdfz；可执行文件与 .pck 必须放在一起。\n'
                '桌面首次启动为窗口模式，菜单与设置内可切换全屏，之后记住您的选择。\n'
                '使用 Vulkan Forward+，需要支持 Vulkan 的显卡和驱动，不提供 OpenGL 回退。\n'
                'Linux 默认原生 Wayland，连接失败时回退 X11；也可传入 --display-driver x11。\n'
                'Linux 需中文系统字体（如 Noto Sans CJK）；若解压工具丢失权限，运行 chmod +x wdfz.x86_64。\n'
                'Windows 包已验证导出，尚未在 Windows 真机验收；未做 Windows 代码签名。\n'
                f'源代码与许可证：https://github.com/wd-fz/wdfz/tree/{revision}\n', encoding='utf-8')
            name = f'wdfz-{RELEASE_VERSION}-{target}-x86_64' if args.release else f'wdfz-{target}-x86_64'
            archive = packages / (name + '.zip')
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
                for path in sorted(directory.iterdir()):
                    bundle.write(path, arcname=f'wdfz-{target}/{path.name}')
            sha = hashlib.sha256()
            with archive.open('rb') as source:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    sha.update(block)
            info.update(passed=True, file=archive.name, bytes=archive.stat().st_size, sha256=sha.hexdigest())
            archive.with_suffix('.zip.sha256').write_text(f'{sha.hexdigest()}  {archive.name}\n')
            archive.with_suffix('.build.json').write_text(json.dumps(info, indent=2) + '\n')
            summary['packages'].append(info)
            print(f'Package ready: {archive.relative_to(ROOT)}', flush=True)
        summary['passed'] = True
    finally:
        (reports / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
