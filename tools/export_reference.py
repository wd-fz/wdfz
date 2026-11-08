#!/usr/bin/env python3
"""Capture independent compatibility fixtures from a running checkout of the original Web game.

Requires Playwright and Chromium. The normal CI suite consumes the committed gzip fixture;
it needs neither the Web repository nor a browser. Do not regenerate expectations from Godot.
"""
import argparse
import base64
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
    parser.add_argument("--inception-only", action="store_true", help="capture original dream/sleep rules, settlements and cinematic")
    parser.add_argument("--maze-patrol-only", action="store_true", help="capture original height-aware patrol paths, gateway and saves")
    parser.add_argument("--anomaly-fx-only", action="store_true", help="capture original world anomaly models, animation and textures")
    parser.add_argument("--falling-props-only", action="store_true", help="capture original cup/cola models, fall animation and ground rays")
    parser.add_argument("--traces-only", action="store_true", help="capture original persistent anomaly traces and stable spatial hashes")
    parser.add_argument("--remaining-death-only", action="store_true", help="capture original fallback death scenes and animations")
    parser.add_argument("--rules-dlc-only", action="store_true", help="capture built-in rules DLC data and original behaviour")
    parser.add_argument("--archive-only", action="store_true", help="capture archive registry, migration and trusted unlocks")
    parser.add_argument("--classmates-only", action="store_true", help="capture original classroom movement and departing students")
    parser.add_argument("--map-only", action="store_true", help="capture original campus plan drawing and road catalogue")
    parser.add_argument("--cyber-only", action="store_true", help="capture original ending monitor, text layout and camera in both orientations")
    parser.add_argument("--world-people-only", action="store_true", help="capture original exchange, gaze, inspection and checkup figures")
    parser.add_argument("--paper-only", action="store_true", help="capture original paper geometry, camera and flight rules")
    parser.add_argument("--death-models-only", action="store_true", help="capture original cup, gaze and moth death models and weather frames")
    parser.add_argument("--checkup-only", action="store_true", help="capture original medical props and all five chart textures")
    parser.add_argument("--death-timelines-only", action="store_true", help="capture original nineteen main death timelines and lift floor displays")
    parser.add_argument("--atmos-props-only", action="store_true", help="capture original emergency signs, shifted props and window silhouettes")
    parser.add_argument("--bell-tails-only", action="store_true", help="capture original bell-tune parameters and eight-note recipes")
    parser.add_argument("--scene-audio-only", action="store_true", help="capture original sensory-scene sound ownership and cancellation")
    parser.add_argument("--maze-death-only", action="store_true", help="capture original maze death meshes and frame matrices")
    parser.add_argument("--crowd-props-only", action="store_true", help="capture original crowd death materials, hands and display texture")
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
            # Ground-ray comparison needs the same q2 asset pack as the exported
            # campus, not q0 placeholders with QUALITY changed after assets load.
            initial_quality=2 if args.falling_props_only or args.traces_only or args.remaining_death_only or args.death_models_only or args.atmos_props_only or args.maze_death_only or args.crowd_props_only else 0
            page.add_init_script("localStorage.setItem('wdfz_pro','1');localStorage.setItem('zw3d_set',JSON.stringify({q:%d,amb:0,vol:0,renderer:'webgl',rv:1}));" % initial_quality)
            page.goto(f"http://127.0.0.1:{server.server_port}/")
            page.wait_for_function("Engine.ready() && Assets.ready(Assets.want())", timeout=180000)
            if args.save_only or args.story_only or args.grading_only or args.crowd_only or args.secret_items_only or args.inception_only or args.maze_patrol_only or args.anomaly_fx_only or args.falling_props_only or args.traces_only or args.remaining_death_only or args.rules_dlc_only or args.archive_only or args.classmates_only or args.map_only or args.cyber_only or args.world_people_only or args.paper_only or args.death_models_only or args.checkup_only or args.death_timelines_only or args.atmos_props_only or args.bell_tails_only or args.scene_audio_only or args.maze_death_only or args.crowd_props_only:
                stem = "crowd_props" if args.crowd_props_only else "maze_death" if args.maze_death_only else "scene_audio" if args.scene_audio_only else "bell_tails" if args.bell_tails_only else "atmos_props" if args.atmos_props_only else "death_timelines" if args.death_timelines_only else "checkup" if args.checkup_only else "death_models" if args.death_models_only else "paper" if args.paper_only else "world_people" if args.world_people_only else "cyber" if args.cyber_only else "map" if args.map_only else "classmates" if args.classmates_only else "archive" if args.archive_only else "rules_dlc" if args.rules_dlc_only else "remaining_death" if args.remaining_death_only else "traces" if args.traces_only else "falling_props" if args.falling_props_only else "anomaly_fx" if args.anomaly_fx_only else "maze_patrol" if args.maze_patrol_only else "inception" if args.inception_only else "secret_items" if args.secret_items_only else "crowd" if args.crowd_only else "grading" if args.grading_only else "routes" if args.story_only else "saves"
                if args.rules_dlc_only:
                    page.evaluate("() => {window.__rulesHooks={};window.__modRegister=GameModules.mod;GameModules.mod=def=>def.init({on:(name,fn)=>window.__rulesHooks[name]=fn,store:spec=>window.__rulesStore=spec,toast:()=>{}});}")
                    page.add_script_tag(path=str(source / "game3d/mods/campus-rules.js"))
                    page.evaluate("() => {GameModules.mod=window.__modRegister;}")
                result = page.evaluate((ROOT / f"tools/reference_{stem}.js").read_text())
                if args.maze_death_only:
                    (ROOT / "assets/campus/maze_death_geometry.json").write_text(json.dumps(result.pop("geometry"),separators=(",",":"))+"\n")
                if args.death_timelines_only:
                    (ROOT / "assets/campus/death_geometry.json").write_text(json.dumps(result.pop("geometry"),separators=(",",":"))+"\n")
                if args.checkup_only or args.atmos_props_only or args.crowd_props_only:
                    texture_dir = ROOT / ("assets/campus/crowd" if args.crowd_props_only else "assets/campus/atmos" if args.atmos_props_only else "assets/campus/checkup")
                    texture_dir.mkdir(parents=True,exist_ok=True)
                    for name,data in result.pop("textures").items():
                        (texture_dir / (name+".png")).write_bytes(base64.b64decode(data.split(",",1)[1]))
                if args.map_only:
                    (ROOT / "assets/campus/map.json").write_text(json.dumps(result.pop("content"),ensure_ascii=False,indent=2)+"\n")
                if args.archive_only:
                    (ROOT / "assets/campus/archive.json").write_text(json.dumps(result.pop("content"),ensure_ascii=False,indent=2)+"\n")
                if args.rules_dlc_only:
                    (ROOT / "assets/campus/rules_dlc.json").write_text(json.dumps(result.pop("content"),ensure_ascii=False,indent=2)+"\n")
                if args.death_models_only:
                    for name,data in result.pop("textures").items():
                        (ROOT / "assets/campus/anomalies" / (name+".png")).write_bytes(base64.b64decode(data.split(",",1)[1]))
                if args.anomaly_fx_only:
                    texture_dir=ROOT / "assets/campus/anomalies"
                    texture_dir.mkdir(parents=True,exist_ok=True)
                    for name,data in result.pop("textures").items():
                        (texture_dir / (name+".png")).write_bytes(base64.b64decode(data.split(",",1)[1]))
                    page.add_script_tag(path=str(ROOT / "tools/export_scenes/vendor/gltf-exporter.js"))
                    page.add_script_tag(path=str(ROOT / "tools/export_scenes/export.js"))
                    model=page.evaluate("window.__wdfzExport('fx','lantern')")
                    (ROOT / "assets/campus/fx/lantern.glb").write_bytes(base64.b64decode(model["glb"]))
                if args.falling_props_only:
                    from export_scenes.export_scenes import externalize_images
                    page.add_script_tag(path=str(ROOT / "tools/export_scenes/vendor/gltf-exporter.js"))
                    page.add_script_tag(path=str(ROOT / "tools/export_scenes/export.js"))
                    textures=ROOT / "assets/campus/textures"
                    for tier in range(5):
                        target_dir=ROOT / f"assets/campus/anomalies/falling/q{tier}"
                        target_dir.mkdir(parents=True,exist_ok=True)
                        page.evaluate("q=>QUALITY=q",tier)
                        for name in ("cup","lid","cola","foam"):
                            model=page.evaluate("name=>window.__wdfzExport('falling',name)",name)
                            (target_dir / f"{name}.glb").write_bytes(externalize_images(base64.b64decode(model["glb"]),textures,"../../../textures/"))
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
