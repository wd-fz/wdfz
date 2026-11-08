#!/usr/bin/env python3
"""Capture independent compatibility fixtures from a running checkout of the original Web game.

Requires Playwright and Chromium. The normal CI suite consumes the committed gzip fixture;
it needs neither the Web repository nor a browser. Do not regenerate expectations from Godot.
"""
import argparse
import functools
import gzip
import json
import subprocess
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="read-only original Web checkout")
    parser.add_argument("--chromium", help="optional installed Chromium executable")
    parser.add_argument("--output", type=Path, default=ROOT / "tests/fixtures/web-reference.json.gz")
    parser.add_argument("--maze-only", action="store_true", help="capture the height-dependent maze fixture instead")
    parser.add_argument("--save-only", action="store_true", help="capture original save/restore scenarios instead")
    parser.add_argument("--story-only", action="store_true", help="capture original route triggers and cinematic paths")
    parser.add_argument("--grading-only", action="store_true", help="render the original post shader and lighting transitions")
    parser.add_argument("--crowd-only", action="store_true", help="capture original lift-crowd rules and death timeline")
    parser.add_argument("--secret-items-only", action="store_true", help="capture original knife and additive starting-gift rules")
    args = parser.parse_args()
    source = args.source.resolve()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:game3d"], cwd=source, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--", "game3d"], cwd=source, text=True)
    if dirty:
        parser.error("The reference game3d directory must be clean.")
    from playwright.sync_api import sync_playwright
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(source)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as p:
            launch = {"args": ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"]}
            if args.chromium:
                launch["executable_path"] = args.chromium
            browser = p.chromium.launch(**launch)
            page = browser.new_page(viewport={"width": 640, "height": 480})
            page.add_init_script("localStorage.setItem('wdfz_pro','1');localStorage.setItem('zw3d_set',JSON.stringify({q:0,amb:0,vol:0,renderer:'webgl',rv:1}));")
            page.goto(f"http://127.0.0.1:{server.server_port}/")
            page.wait_for_function("Engine.ready() && Assets.ready(Assets.want())", timeout=180000)
            if args.save_only or args.story_only or args.grading_only or args.crowd_only or args.secret_items_only:
                stem = "secret_items" if args.secret_items_only else "crowd" if args.crowd_only else "grading" if args.grading_only else "routes" if args.story_only else "saves"
                result = page.evaluate((ROOT / f"tools/reference_{stem}.js").read_text())
                result["game3d_tree"] = tree
                target = ROOT / f"tests/fixtures/{stem if stem != 'saves' else 'save'}-reference.json.gz" if args.output == ROOT / "tests/fixtures/web-reference.json.gz" else args.output
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(gzip.compress((json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n").encode(), mtime=0))
                print(f"Original {stem} scenarios → {target}")
                browser.close()
                return
            if args.maze_only:
                maze = page.evaluate('''() => {
                  const points=[];
                  for(const h of [-8,-4,0,4,8])for(let z=-38.6;z<39;z+=1.37)for(let x=-23.6;x<24;x+=1.31){
                    const g=VoidMaze.groundAt(x,z,h+MAZE_CFG.step);
                    points.push([x,z,h,VoidMaze.depthAt(x,z,1/3,h),Number.isFinite(g)?g:null]);
                  }
                  return {points,reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc'};
                }''')
                maze["game3d_tree"] = tree
                target = ROOT / "tests/fixtures/maze-reference.json.gz" if args.output == ROOT / "tests/fixtures/web-reference.json.gz" else args.output
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(gzip.compress((json.dumps(maze, ensure_ascii=False, separators=(",", ":")) + "\n").encode(), mtime=0))
                print(f"{len(maze['points'])} maze depth/height samples → {target}")
                browser.close()
                return
            known = [p.stem for p in (ROOT / "assets/campus/layout").glob("*.json") if p.stem not in ["campus", "out"]]
            result = page.evaluate(r'''ids => {
      S.mode='out';S.room=null;S.floorY=0;S.viol=0;S.seated=false;
      Object.keys(OPENDOORS).forEach(k=>delete OPENDOORS[k]);
      const scenes=[],excluded=[],radius=PRAD-0.01;
      const sample=(x,y,room)=>{
        const depth=Collision.depth(x,y,radius,room);
        if(Number.isFinite(depth) && depth>0 && depth<0.025)return null;
        return [Math.round((x-(room?room.cx:0))*U2M*1e5)/1e5,Math.round((y-(room?room.cy:0))*U2M*1e5)/1e5,depth>0];
      };
      ids.sort().forEach(id=>{
        const r=INTERIORS[id];if(!r)return; if(r.stairwell||r.spiral||id==='lift_dream'){excluded.push({id,reason:'height-dependent collision; covered separately'});return;}
        SpaceLayout.ensureRoom(r);
        const points=[];
        for(let y=0;y<r.rows;y++)for(let x=0;x<r.cols;x++)for(const q of [[.5,.5],[.18,.72]]){
          const v=sample(r.ox+(x+q[0])*r.tw,r.oy+(y+q[1])*r.th,r);if(v)points.push(v);
        }
        scenes.push({id,points});
      });
      SpaceLayout.ensureOutside();const points=[];
      for(let y=(BOUND.y0+3)*SC;y<=(BOUND.y1-3)*SC;y+=47.1)for(let x=(BOUND.x0+3)*SC;x<=(BOUND.x1-3)*SC;x+=43.7){const v=sample(x,y,null);if(v)points.push(v);}
      scenes.push({id:'out',points});
      const clock=[];
      for(let t=440;t<1500;t+=.5)clock.push([t,rateAt(t),needWhere(t),(S.tsec=t,isNight()),fmtClock(t),clockBoundary(t)]);
      for(const t of [705,705+14/60,705+20/60,1349.99,1350,1499.99])clock.push([t,rateAt(t),needWhere(t),(S.tsec=t,isNight()),fmtClock(t),clockBoundary(t)]);
      const camera=[];
      S.mode='out';S.room=null;S.dead=false;S.floorY=0;S.pitch=0;S.ang=0;GLR.gazeShake=0;
      VisualState.camera.walkPhase=0;VisualState.camera.eyeH=1.65;VisualState.camera.fov=72;
      const stages=[[false,true,false,true,16/9,0],[false,true,true,true,16/9,0],
        [true,false,false,true,16/9,0],[false,false,false,true,16/9,.35],
        [false,true,false,false,16/9,0],[false,true,true,false,12,0]];
      for(const stage of stages)for(let i=0;i<60;i++){
        const [seated,moving,run,shake,aspect,drop]=stage;
        S.seated=seated;S.moving=moving;S.run=run;SHAKE_ON=shake;S.eyeLift=-drop;GLR.cam.aspect=aspect;
        ThreeBackend.syncCamera(1/60);
        camera.push([1/60,...stage,GLR.cam.position.y,GLR.cam.fov,GLR.cam.near]);
      }
      return {excluded,camera,quality:Quality.profiles.map(q=>({rain:q.rain,moths:q.moths,shadows:!!q.shadow})),reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',radius:radius*U2M,scenes,clock};
    }''', known)
            result["game3d_tree"] = tree
            args.output.parent.mkdir(parents=True, exist_ok=True)
            raw = (json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
            args.output.write_bytes(gzip.compress(raw, mtime=0))
            print(f"{len(result['scenes'])} scenes, {sum(len(r['points']) for r in result['scenes'])} collision samples, "
                  f"{len(result['clock'])} clock samples, {len(result['camera'])} camera frames → {args.output}")
            browser.close()
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
