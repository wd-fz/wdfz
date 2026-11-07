"""从旧 Web 版仓库导出建筑模型为 glb（建筑不能变：几何全部来自旧版自己的建模函数）。

用法：
  python3 tools/export_scenes/export_scenes.py --old <wd-fz.github.io 检出目录> [--quality 2] [--only teach1,out]

在无头 Chromium 里打开旧版首页，等引擎就绪后注入 vendor/gltf-exporter.js 与 export.js，
逐个调用 buildRoomGeometry / buildOutdoorGeometry，烘焙实例、按材质合并后写到
assets/campus/scenes/<场景>.glb；贴图去重后放 assets/campus/textures/，glb 以相对路径引用；
index.json 记录名节点及其 userData。
"""
import argparse, base64, hashlib, json, os, struct, threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CHROME = os.environ.get('CHROMIUM_EXECUTABLE') or '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome'


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def externalize_images(glb, tex_dir, rel):
    """把 glb 内嵌的贴图按内容哈希写成独立 PNG（多个场景共用一份），glb 改为相对 URI 引用。"""
    jlen = struct.unpack('<I', glb[12:16])[0]
    doc = json.loads(glb[20:20 + jlen])
    bin_off = 20 + jlen
    blen = struct.unpack('<I', glb[bin_off:bin_off + 4])[0]
    blob = glb[bin_off + 8:bin_off + 8 + blen]
    views = doc.get('bufferViews', [])
    drop = set()
    for img in doc.get('images', []):
        if 'bufferView' not in img:
            continue
        v = views[img['bufferView']]
        data = blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
        ext = '.png' if img.get('mimeType') == 'image/png' else '.jpg'
        name = hashlib.sha1(data).hexdigest()[:16] + ext
        path = tex_dir / name
        if not path.exists():
            path.write_bytes(data)
        drop.add(img.pop('bufferView'))
        img.pop('mimeType', None)
        img['uri'] = rel + name
    remap, out = {}, bytearray()
    kept = []
    for i, v in enumerate(views):
        if i in drop:
            continue
        data = blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
        while len(out) % 4:
            out.append(0)
        v = dict(v, byteOffset=len(out))
        out += data
        remap[i] = len(kept)
        kept.append(v)
    doc['bufferViews'] = kept
    for acc in doc.get('accessors', []):
        if 'bufferView' in acc:
            acc['bufferView'] = remap[acc['bufferView']]
    while len(out) % 4:
        out.append(0)
    doc['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + 8 + len(out)
    return (struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(js), 0x4E4F534A) + js
            + struct.pack('<II', len(out), 0x004E4942) + bytes(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--old', required=True, help='旧仓库 wd-fz.github.io 的检出目录')
    ap.add_argument('--quality', type=int, default=2)
    ap.add_argument('--only', default='')
    ap.add_argument('--layout-only', action='store_true', help='只导出布局与碰撞 JSON')
    ap.add_argument('--out', default=str(REPO / 'assets' / 'campus'))
    a = ap.parse_args()
    out = Path(a.out) / 'scenes'
    tex = Path(a.out) / 'textures'
    out.mkdir(parents=True, exist_ok=True)
    tex.mkdir(parents=True, exist_ok=True)
    srv = ThreadingHTTPServer(('127.0.0.1', 0), partial(Quiet, directory=a.old))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{srv.server_port}/'
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=CHROME if Path(CHROME).exists() else None,
                              args=['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        ctx = b.new_context(viewport={'width': 640, 'height': 480})
        ctx.add_init_script("localStorage.setItem('wdfz_pro','1');localStorage.setItem('zw3d_set',JSON.stringify({q:%d,amb:0,vol:0,renderer:'webgl',rv:1}));" % a.quality)
        pg = ctx.new_page()
        errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        pg.goto(url)
        pg.wait_for_function('Engine.ready()', timeout=180000)
        pg.wait_for_function('Assets.ready(Assets.want())', timeout=180000)
        pg.add_script_tag(path=str(HERE / 'vendor' / 'gltf-exporter.js'))
        pg.add_script_tag(path=str(HERE / 'export.js'))
        rooms = pg.evaluate('Object.keys(INTERIORS)')
        todo = ['out'] + rooms
        if a.only:
            want = set(a.only.split(','))
            todo = [t for t in todo if t in want]
            if a.only in ('patrol', 'figures'):
                todo = []
        patrol_dir = Path(a.out) / 'patrol'
        patrol_dir.mkdir(parents=True, exist_ok=True)
        if not a.only or 'patrol' in a.only.split(','):
            data = pg.evaluate('window.__wdfzPatrolData()')
            (patrol_dir / 'patrol_data.json').write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
            fig = pg.evaluate("window.__wdfzExport('patrol', 'patrol_figure')")
            (patrol_dir / 'patrol_figure.glb').write_bytes(externalize_images(base64.b64decode(fig['glb']), tex, '../textures/'))
            print(f"patrol: data {(patrol_dir / 'patrol_data.json').stat().st_size/1e3:.0f} kB, figure {(patrol_dir / 'patrol_figure.glb').stat().st_size/1e3:.0f} kB", flush=True)
            if a.only == 'patrol':
                todo = []
        if not a.only or 'figures' in a.only.split(','):
            fig_dir = Path(a.out) / 'figures'
            fig_dir.mkdir(parents=True, exist_ok=True)
            for kind in ['tall', 'roam', 'person', 'teacher', 'neck', 'sit']:
                r = pg.evaluate("([k,i])=>window.__wdfzExport(k,i)", ['figure', kind])
                data = externalize_images(base64.b64decode(r['glb']), tex, '../textures/')
                (fig_dir / f'{kind}.glb').write_bytes(data)
                print(f'figure {kind}: {len(data)/1e3:.0f} kB', flush=True)
            if a.only == 'figures':
                todo = []
        index_path = out / 'index.json'
        index = json.loads(index_path.read_text()) if index_path.exists() else {}
        layout_dir = Path(a.out) / 'layout'
        layout_dir.mkdir(parents=True, exist_ok=True)
        if not a.only:
            common = pg.evaluate("window.__wdfzLayout('campus')")
            (layout_dir / 'campus.json').write_text(json.dumps(common, ensure_ascii=False, indent=1))
        for sid in todo:
            kind = 'out' if sid == 'out' else 'room'
            lay = pg.evaluate('([k,i])=>window.__wdfzLayout(k,i)', [kind, sid])
            (layout_dir / f'{sid}.json').write_text(json.dumps(lay, ensure_ascii=False, separators=(',', ':')))
            if a.layout_only:
                continue
            r = pg.evaluate('([k,i])=>window.__wdfzExport(k,i)', [kind, sid])
            data = externalize_images(base64.b64decode(r['glb']), tex, '../textures/')
            (out / f'{sid}.glb').write_bytes(data)
            index[sid] = r['meta']
            print(f'{sid}: {len(data)/1e6:.2f} MB, named={len(r["meta"]["named"])}', flush=True)
        index_path.write_text(json.dumps(index, ensure_ascii=False, indent=1, sort_keys=True))
        if errs:
            print('page errors:', errs[:5])
        b.close()
    srv.shutdown()


if __name__ == '__main__':
    main()
