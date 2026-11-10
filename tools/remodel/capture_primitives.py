#!/usr/bin/env python3
"""Record the primitives of the old build's figures (model/figure.js figGeo) into tools/remodel/primitives/.

  python3 tools/remodel/capture_primitives.py --old <wd-fz.github.io checkout>

The old page builds each figure itself; capture.js only listens to the Kit primitive calls (rod, blob, bevel, cyl,
box) and writes down their arguments. The result is the input of remodel.py.
"""
import argparse
import json
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
CHROME = '/opt/pw-browsers/chromium'
KINDS = ['tall', 'roam', 'person', 'teacher', 'neck', 'sit']


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--old', required=True)
    a = ap.parse_args()
    out = HERE / 'primitives'
    out.mkdir(exist_ok=True)
    srv = ThreadingHTTPServer(('127.0.0.1', 0), partial(Quiet, directory=a.old))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=CHROME if Path(CHROME).exists() else None,
                              args=['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        ctx = b.new_context(viewport={'width': 640, 'height': 480})
        # Quality 4 ("真实"): the old build then uses its smooth-LOD segment counts; the primitive parameters are the same.
        ctx.add_init_script("localStorage.setItem('wdfz_pro','1');localStorage.setItem('zw3d_set',JSON.stringify({q:4,amb:0,vol:0,renderer:'webgl',rv:1}));")
        pg = ctx.new_page()
        pg.goto(f'http://127.0.0.1:{srv.server_port}/')
        pg.wait_for_function('Engine.ready()', timeout=180000)
        pg.wait_for_function('Assets.ready(Assets.want())', timeout=180000)
        pg.add_script_tag(path=str(HERE / 'capture.js'))
        for kind in KINDS:
            data = pg.evaluate('k => window.__wdfzFigurePrims(k)', kind)
            (out / f'figure_{kind}.json').write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
            print(f'{kind}: {len(data["prims"])} primitives')
        b.close()
    srv.shutdown()


if __name__ == '__main__':
    main()
