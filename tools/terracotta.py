#!/usr/bin/env python3
"""Fetch pinned, SHA256-verified Terracotta binaries; never download at game runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.4.2'
SOURCE = 'https://github.com/burningtnt/Terracotta/tree/70d542156377b316659b4ec2ac62341a43ddc4b2'
ASSETS = {
    'linux': ('linux-x86_64-pkg.tar.gz', '675c4fd6c74d49ed8165151ba2be5b6582e0af20fb6d912074543c2484b1e10a'),
    'windows': ('windows-x86_64-pkg.tar.gz', '07ebe139e3ca5f74576e58b1a96efe59abdfbe148d3f1a49bfdca8b6f70745f0'),
    'android': ('android-arm64v8a.so', 'fc426710de5f53ae5b6350fdffe1012082992dac5b9d93ea5e86c0e56af5567a'),
}


def prepare(platform):
    suffix, digest = ASSETS[platform]
    name = f'terracotta-{VERSION}-{suffix}'
    cache = ROOT / 'build/deps/terracotta'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / name
    if not archive.exists():
        temporary = archive.with_suffix(archive.suffix + '.part')
        with urllib.request.urlopen(f'https://github.com/burningtnt/Terracotta/releases/download/v{VERSION}/{name}', timeout=120) as source, temporary.open('wb') as output:
            shutil.copyfileobj(source, output)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        archive.unlink()
        raise RuntimeError(f'Terracotta SHA256 mismatch: {name}')
    directory = cache / platform
    directory.mkdir(exist_ok=True)
    target = directory / ('libterracotta.so' if platform == 'android' else 'terracotta.exe' if platform == 'windows' else 'terracotta')
    if platform == 'android':
        shutil.copy2(archive, target)
    else:
        # Extract just the expected regular executable. No archive paths/symlinks are trusted.
        member_name = f'terracotta-{VERSION}-{platform}-x86_64' + ('.exe' if platform == 'windows' else '')
        temporary = target.with_suffix('.verified-part')
        with tarfile.open(archive) as package:
            member = package.getmember(member_name)
            if not member.isfile():
                raise RuntimeError('Terracotta asset is not a regular file')
            with package.extractfile(member) as source, temporary.open('wb') as output:
                shutil.copyfileobj(source, output)
        temporary.replace(target)
        target.chmod(0o755)
    return target


def bundle(platform, directory):
    source = prepare(platform)
    directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, directory / source.name)
    for name in ('LICENSE', 'NOTICE.md'):
        shutil.copy2(ROOT / 'third_party/terracotta' / name, directory / name)
    (directory / 'dependency.json').write_text(json.dumps({'version': VERSION, 'source': SOURCE,
        'archive_sha256': ASSETS[platform][1]}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=ASSETS, required=True)
    print(prepare(parser.parse_args().platform))
