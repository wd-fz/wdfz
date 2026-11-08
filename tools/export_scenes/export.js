/* 在旧 Web 版页面里运行：用旧版自己的建模函数建场景，烘焙实例、按材质合并，导出 glb。
   window.__wdfzExport(kind, id) → base64 glb。kind = 'room' | 'out' | 'doors'。 */
(function(){
  'use strict';
  var T = window.THREE;
  var GEO_CACHE = {};
  function matKey(m){ return m.uuid; }
  /* 模型包里的顶点属性可能是量化的 Int16 / Uint8（normalized）。glTF 那边要 KHR_mesh_quantization，Godot 不支持；
     烘焙矩阵前也必须先还原成浮点，否则会在整数上做变换 */
  function toFloat(a){
    if(!a) return a;
    var n = a.count, s = a.itemSize, out = new Float32Array(n * s), i;
    var get = [a.getX, a.getY, a.getZ, a.getW];
    for(i = 0; i < n; i++) for(var k = 0; k < s; k++) out[i * s + k] = get[k].call(a, i);
    return new T.BufferAttribute(out, s);
  }
  /* 把一个网格（含实例化网格）的几何烘焙到世界坐标，实例颜色写进顶点色 */
  function bake(o, out){
    var src = o.geometry; if(!src || !src.attributes.position) return;
    if(o.userData && o.userData.grassCell) return;          /* 草随画质增减，属表现层，Godot 里用 MultiMesh 另做 */
    var mats = Array.isArray(o.material) ? o.material : [o.material];
    var count = o.isInstancedMesh ? o.count : 1;
    var im = new T.Matrix4(), wm = new T.Matrix4(), col = new T.Color();
    var base = new T.BufferGeometry();
    ['position','normal','uv','color'].forEach(function(k){ if(src.attributes[k]) base.setAttribute(k, toFloat(src.attributes[k])); });
    var n = base.attributes.position.count;
    if(src.index) base.setIndex(Array.from(src.index.array)); else { var ix = new Array(n); for(var q = 0; q < n; q++) ix[q] = q; base.setIndex(ix); }
    if(!base.attributes.normal) base.computeVertexNormals();
    if(!base.attributes.uv) base.setAttribute('uv', new T.BufferAttribute(new Float32Array(n * 2), 2));
    for(var i = 0; i < count; i++){
      wm.copy(o.matrixWorld);
      if(o.isInstancedMesh){ o.getMatrixAt(i, im); wm.multiply(im); }
      var g = base.clone(); g.applyMatrix4(wm);
      if(wm.determinant() < 0){ var a = g.index.array; for(var t = 0; t < a.length; t += 3){ var tmp = a[t+1]; a[t+1] = a[t+2]; a[t+2] = tmp; } }
      var ic = o.isInstancedMesh && o.instanceColor ? (o.getColorAt(i, col), col.clone()) : null;
      if(ic || g.attributes.color){
        var c = new Float32Array(n * 3), k, has = !!g.attributes.color;
        for(k = 0; k < n; k++){
          var r = 1, gg = 1, b = 1;
          if(has){ r = g.attributes.color.getX(k); gg = g.attributes.color.getY(k); b = g.attributes.color.getZ(k); }
          if(ic){ r *= ic.r; gg *= ic.g; b *= ic.b; }
          c[k*3] = r; c[k*3+1] = gg; c[k*3+2] = b;
        }
        g.setAttribute('color', new T.BufferAttribute(c, 3));
      }
      var groups = (src.groups && src.groups.length && mats.length > 1) ? src.groups : [{start:0, count:g.index.count, materialIndex:0}];
      groups.forEach(function(gr){
        var m = mats[gr.materialIndex || 0]; if(!m || m.visible === false) return;
        var part = groups.length > 1 ? sub(g, gr.start, gr.count) : g;
        var key = matKey(m);
        (out[key] = out[key] || {mat:m, geos:[]}).geos.push(part);
      });
    }
  }
  function sub(g, start, count){
    var r = g.clone(); r.setIndex(Array.from(g.index.array.slice(start, start + count))); return r;
  }
  function stdMat(m, vc){
    /* glTF 只认标准材质；Phong / Lambert 按颜色、贴图、自发光、透明换成 Standard */
    var s = m.isMeshStandardMaterial ? m.clone() : (m.isMeshBasicMaterial ? m.clone() : new T.MeshStandardMaterial({
      color:m.color, map:m.map||null, normalMap:m.normalMap||null, emissive:m.emissive||new T.Color(0),
      emissiveMap:m.emissiveMap||null, transparent:m.transparent, opacity:m.opacity, alphaTest:m.alphaTest,
      side:m.side, roughness:m.isMeshPhongMaterial ? Math.max(0.2, 1 - (m.shininess||30) / 100) : 0.95, metalness:0 }));
    s.vertexColors = !!vc; s.name = (m.name || m.type) + (m.userData && m.userData.matKey ? ':' + m.userData.matKey : '');
    /* 灯光模块逐帧改色的几种材质：打上固定名字，Godot 里按名字找回来 */
    var G = window.GLR || {}, M = window.MATS || {};
    [[G.lampHeadMat, 'lampHead'], [G.winSkyMat, 'winSky'], [G.winLitMat, 'winLit'], [M.emit, 'emit'], [M.emitDying, 'emitDying']].forEach(function(p){
      if(p[0] && p[0] === m) s.name = 'wdfz_live:' + p[1];
    });
    return s;
  }
  function b64(f32){
    var bytes = new Uint8Array(f32.buffer), s = '', CH = 0x8000;
    for(var i = 0; i < bytes.length; i += CH) s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    return btoa(s);
  }
  /* 实例化网格：几何只存一份（局部坐标），实例变换按 Godot Transform3D 顺序（基向量 x、y、z，原点）写进 extras */
  function instanced(o, root, idx){
    var mats = Array.isArray(o.material) ? o.material : [o.material];
    if(mats.length !== 1 || !mats[0] || mats[0].visible === false || o.count < 1) return false;
    var src = o.geometry, geo = GEO_CACHE[src.uuid];
    if(!geo){
      geo = GEO_CACHE[src.uuid] = new T.BufferGeometry();
      ['position','normal','uv','color'].forEach(function(k){ if(src.attributes[k]) geo.setAttribute(k, toFloat(src.attributes[k])); });
      if(src.index) geo.setIndex(src.index);
      if(!geo.attributes.normal) geo.computeVertexNormals();
    }
    var mesh = new T.Mesh(geo, stdMat(mats[0], !!o.instanceColor || !!src.attributes.color));
    mesh.name = 'inst' + idx;
    var rel = new T.Matrix4().copy(root.matrixWorld).invert().multiply(o.matrixWorld);
    var xf = new Float32Array(o.count * 12), cf = o.instanceColor ? new Float32Array(o.count * 3) : null;
    var m = new T.Matrix4(), w = new T.Matrix4(), c = new T.Color(), e;
    for(var i = 0; i < o.count; i++){
      o.getMatrixAt(i, m); w.multiplyMatrices(rel, m); e = w.elements;
      xf.set([e[0], e[1], e[2], e[4], e[5], e[6], e[8], e[9], e[10], e[12], e[13], e[14]], i * 12);
      if(cf){ o.getColorAt(i, c); cf[i*3] = c.r; cf[i*3+1] = c.g; cf[i*3+2] = c.b; }
    }
    mesh.userData = {wdfz_instances: b64(xf), wdfz_count: o.count};
    if(cf) mesh.userData.wdfz_colors = b64(cf);
    root.add(mesh);
    return true;
  }
  function merged(group, name){
    var root = new T.Group(); root.name = name;
    group.updateMatrixWorld(true); root.updateMatrixWorld(true);
    var buckets = {}, n = 0;
    group.traverse(function(o){
      if(!o.isMesh || !isVisible(o) || (o.userData && o.userData.grassCell)) return;
      if(o.isInstancedMesh && instanced(o, root, n++)) return;
      bake(o, buckets);
    });
    Object.keys(buckets).forEach(function(key, i){
      var b = buckets[key], needColor = b.geos.some(function(x){ return !!x.attributes.color; });
      b.geos.forEach(function(x){
        if(needColor && !x.attributes.color){ var w = new Float32Array(x.attributes.position.count * 3).fill(1); x.setAttribute('color', new T.BufferAttribute(w, 3)); }
      });
      var geo = window.mergeGeometries(b.geos, false);
      if(!geo) return;
      var mesh = new T.Mesh(geo, stdMat(b.mat, needColor)); mesh.name = name + '_m' + i; root.add(mesh);
    });
    return root;
  }
  function isVisible(o){ for(var p = o; p; p = p.parent){ if(!p.visible) return false; } return true; }
  /* 有名字的一级子节点（门扇、电梯门、告示）各自单独成节点，保留局部变换，方便 Godot 里动起来 */
  function splitNamed(g){
    var named = [];
    g.children.slice().forEach(function(c){ if(c.name){ named.push(c); g.remove(c); } });
    return named;
  }
  function exportScene(g, label){
    GEO_CACHE = {};
    g.updateMatrixWorld(true);
    var named = splitNamed(g), scene = new T.Scene(), meta = {named:[]};
    scene.add(merged(g, label));
    named.forEach(function(c, i){
      c.updateMatrixWorld(true);
      var inv = new T.Matrix4().copy(c.matrixWorld).invert();
      /* 名节点：几何烘焙到它自己的局部坐标，节点放回原位 */
      var holder = new T.Group(); holder.name = c.name + '__' + i;
      c.matrixWorld.decompose(holder.position, holder.quaternion, holder.scale);
      var saveParent = c.parent; c.position.set(0,0,0); c.quaternion.identity(); c.scale.set(1,1,1);
      var tmp = new T.Group(); tmp.add(c); tmp.updateMatrixWorld(true);
      holder.add(merged(tmp, c.name + '__' + i + '_geo'));
      holder.userData = JSON.parse(JSON.stringify(c.userData || {}));
      scene.add(holder);
      meta.named.push({name:c.name, userData:holder.userData});
    });
    return new Promise(function(res, rej){
      new window.GLTFExporter().parse(scene, function(buf){
        var bytes = new Uint8Array(buf), s = '', CH = 0x8000;
        for(var i = 0; i < bytes.length; i += CH) s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
        res({glb:btoa(s), meta:meta});
      }, rej, {binary:true, onlyVisible:true, maxTextureSize:2048});
    });
  }
  /* 普通房门：旧版每次开关都按 OPENDOORS 重建门扇（瞬间换姿态）。这里每扇门各导出关、开两份，Godot 里切换可见性 */
  function doorVariants(R, g){
    var old = g.getObjectByName('doorleaves'); if(old) g.remove(old);
    var D = window.OPENDOORS, list = [];
    (R.doorSpecs || []).forEach(function(d){
      var key = window.doorKeyAt(R, d.x, d.y), was = D[key];
      [['closed', 0], ['open', 1]].forEach(function(v){
        if(v[1]) D[key] = 1; else delete D[key];
        var leaf = window.buildDoorLeaves({id:R.id, doorSpecs:[d]});
        leaf.name = 'door_' + v[0] + '__' + d.x + '_' + d.y;
        leaf.userData = {door_key:key, c:d.x, r:d.y, state:v[0]};
        list.push(leaf);
      });
      if(was) D[key] = was; else delete D[key];
    });
    list.forEach(function(x){ g.add(x); });
  }
  /* 巡察者人形：旧版 patAddFig 的 teacher 人形（纯黑，不受光）加装备几何（夹板等，顶点色） */
  function patrolFigure(){
    var T2 = window.THREE, g = new T2.Group();
    var body = window.figMesh('teacher', new T2.MeshBasicMaterial({color:0x040506}), 1.12); g.add(body);
    var gear = new T2.Mesh(window.patGearGeo(), new T2.MeshBasicMaterial({vertexColors:true, color:0x555555}));
    gear.scale.setScalar(1.12); g.add(gear);
    return g;
  }
  /* 巡察世界的数据：栅格位图、导航图（边不带折线）、路线、区域与速度常数——全部取旧版运行时的值 */
  function patrolData(){
    var graph = window.PatrolNav.graph(), edges = graph.edges.map(function(e){ return {a:e.a, b:e.b, kind:e.kind, weight:e.weight}; });
    var nodes = {}; Object.keys(graph.nodes).forEach(function(k){ var n = graph.nodes[k]; nodes[k] = {scene:n.scene, x:Math.round(n.x * 10000) / 10000, y:Math.round(n.y * 10000) / 10000, fy:Math.round((n.fy || 0) * 10000) / 10000}; });
    return {geometry:window.PATROL_GEOMETRY, route:window.PATROL_ROUTE, zones:window.PATROL_ZONES,
      graph:{nodes:nodes, edges:edges, patrolEdges:graph.patrolEdges},
      consts:{speed:window.PAT_SPEED, chase:window.PAT_CHASE, see:window.PAT_SEE, catch:window.PAT_CATCH, body:window.PAT_BODY, nav_n:window.PAT_NAV_N, cfg:window.PAT_CFG,
        lockers:window.LOCKER_CELLS},
      stair_geometry:window.StairGeometry.config};
  }
  window.__wdfzPatrolData = patrolData;
  window.__wdfzHandPlace = function(){ return window.HAND_PLACE; };
  window.__wdfzExport = function(kind, id){
    if(kind === 'patrol') return exportScene(patrolFigure(), 'patrol_figure');
    if(kind === 'hand'){   /* 第一人称的手与手里的东西：id = torch_R / torch_L / phone_R / … / brolly_L；原点在握持中心，前方 -z */
      var parts = id.split('_'), item = parts[0], side = parts[1] === 'L' ? -1 : 1;
      var hand = window.handArm(side);
      hand.children[0].geometry = window.handGeo(side, item);
      var it = window.makeHandItem(item);
      it.scale.x = (item === 'brolly' || side > 0) ? 1 : -1;
      hand.add(it);
      return exportScene(hand, 'hand_' + id);
    }
    if(kind === 'fx'){   /* 异象／死亡演出里的东西（旧版 fxMesh）：手、头、突脸、笑脸、长脖子的头、钟…… */
      var xg = new T.Group();
      xg.add(window.fxMesh(id));
      return exportScene(xg, 'fx_' + id);
    }
    if(kind === 'prop'){   /* 一件家具／设备（旧版 Kit.asset，合并网格）：结局分镜的布景用，原点在脚下 */
      var pk = new window.Kit();
      pk.asset(id, 0, 0, 0, 0, {merge:true, mat:{emit:''}});
      return exportScene(pk.build(), 'prop_' + id);
    }
    if(kind === 'figure'){   /* 旧版 figMesh 的人形（tall / roam / person / teacher / neck / sit），白色，颜色由 Godot 侧给 */
      var fg = new T.Group();
      fg.add(window.figMesh(id, new T.MeshBasicMaterial({color:0xffffff, vertexColors:true}), 1));
      return exportScene(fg, 'figure_' + id);
    }
    if(kind === 'out') return exportScene(window.buildOutdoorGeometry(), 'outdoor');
    var R = window.INTERIORS[id], g = window.buildRoomGeometry(R);
    doorVariants(R, g);
    return exportScene(g, id);
  };
})();

/* ---- 布局与碰撞：只读旧版自己的数据（SpaceLayout / FURN_SOLID / roofSolids / OUT_SOLID / 门表），不重新推导 ---- */
(function(){
  'use strict';
  var U = window.U2M;
  function round(v){ return Math.round(v * 10000) / 10000; }
  function box(x0, z0, x1, z1, kind, extra){
    var b = {k:kind, x0:round(Math.min(x0, x1)), z0:round(Math.min(z0, z1)), x1:round(Math.max(x0, x1)), z1:round(Math.max(z0, z1))};
    return extra ? Object.assign(b, extra) : b;
  }
  /* 整格墙：同一行连续的墙格并成一条，再把上下宽度相同的条并成块，减少碰撞体数量（占地不变） */
  function mergeCells(cells, R, toM){
    var rows = {}, strips = [], out = [];
    cells.forEach(function(c){ (rows[c[1]] = rows[c[1]] || []).push(c[0]); });
    Object.keys(rows).map(Number).sort(function(a,b){return a-b;}).forEach(function(r){
      var xs = rows[r].sort(function(a,b){return a-b;}), s = xs[0], p = xs[0];
      for(var i = 1; i <= xs.length; i++){
        if(i < xs.length && xs[i] === p + 1){ p = xs[i]; continue; }
        strips.push({c0:s, c1:p, r0:r, r1:r}); if(i < xs.length){ s = p = xs[i]; }
      }
    });
    strips.forEach(function(s){
      var hit = out.filter(function(o){ return o.c0 === s.c0 && o.c1 === s.c1 && o.r1 === s.r0 - 1; })[0];
      if(hit) hit.r1 = s.r0; else out.push(s);
    });
    return out.map(function(o){ return toM(R.ox + o.c0 * R.tw, R.oy + o.r0 * R.th, R.ox + (o.c1 + 1) * R.tw, R.oy + (o.r1 + 1) * R.th, 'wall'); });
  }
  function pose(R, x, y, ang){ return {x:x, y:y, ang:ang, scene_x:round((x - R.cx) * U), scene_z:round((y - R.cy) * U)}; }
  /* 旧版 doEnterRoom 没有指定落点时的位置：车库固定点，其余先放南墙内侧中间，再找出入口（'O'，没有就 'O'/'S'/'L'）旁能站的一格 */
  function defaultSpawn(R){
    var x, y, ang = window.S.ang;
    if(R.id === 'garage1'){ x = R.ox + R.w - 5 * R.tw; y = R.oy + 13 * R.th; ang = -Math.PI / 2; }
    else { x = R.ox + R.w / 2; y = R.oy + R.h - 2 * R.th; ang = null; }
    var en = null;
    try{ en = window.entryNear(R, ['O']) || window.entryNear(R, ['O', 'S', 'L']); }catch(e){}
    if(en){ x = en.x; y = en.y; ang = en.ang; }
    return pose(R, x, y, ang);
  }
  /* 开局：坐在本人座位上（ClassroomLayout.anchor）；站起来的位置用旧版 leaveSeat 现场算 */
  /* 所有座位格（'P'）：坐下的锚点（ClassroomLayout.anchor）与旧版 leaveSeat 算出的起身位置 */
  function seatList(R){
    var out = [], L = window.ClassroomLayout, S = window.S;
    for(var r = 0; r < R.rows; r++) for(var c = 0; c < R.cols; c++){
      if(R.grid[r][c] !== 'P') continue;
      var seat = L.seat(R.id, c, r), a = L.anchor(R, seat);
      var keep = {mode:S.mode, room:S.room, x:S.x, y:S.y, ang:S.ang, seated:S.seated, seat:S.seat};
      S.mode = 'in'; S.room = R.id; S.x = a.x; S.y = a.y; S.ang = a.ang; S.seated = true; S.seat = seat;
      window.leaveSeat();
      var stand = pose(R, S.x, S.y, a.ang);
      Object.assign(S, keep);
      out.push({c:c, r:r, seat_id:seat.seatId, facing:seat.facing, seated:pose(R, a.x, a.y, a.ang), stand:stand});
    }
    return out;
  }
  function seatStart(R){
    var L = window.ClassroomLayout, a = L.anchor(R, L.ownSeat), S = window.S;
    var keep = {mode:S.mode, room:S.room, x:S.x, y:S.y, ang:S.ang, seated:S.seated, seat:S.seat};
    S.mode = 'in'; S.room = R.id; S.x = a.x; S.y = a.y; S.ang = a.ang; S.seated = true; S.seat = L.seat(R.id, L.ownSeat.col, L.ownSeat.row);
    window.leaveSeat();
    var stand = pose(R, S.x, S.y, a.ang);
    Object.assign(S, keep);
    return {seated:pose(R, a.x, a.y, a.ang), stand:stand};
  }
  function roomLayout(id){
    var R = window.INTERIORS[id];
    window.SpaceLayout.ensureRoom(R);
    function toM(x0, y0, x1, y1, kind, extra){ return box((x0 - R.cx) * U, (y0 - R.cy) * U, (x1 - R.cx) * U, (y1 - R.cy) * U, kind, extra); }
    var walls = [], boxes = [], doors = [], stairs = [], grid = [], r, c;
    for(r = 0; r < R.rows; r++){
      grid.push(R.grid[r].join(''));
      for(c = 0; c < R.cols; c++){
        var t = R.grid[r][c], cx = R.ox + (c + 0.5) * R.tw, cy = R.oy + (r + 0.5) * R.th;
        if(t === '#'){ walls.push([c, r]); continue; }
        if(t === 'S'){ stairs.push(toM(R.ox + c * R.tw, R.oy + r * R.th, R.ox + (c + 1) * R.tw, R.oy + (r + 1) * R.th, 'stair', {c:c, r:r})); continue; }
        if(t === '='){ doors.push(toM(R.ox + c * R.tw, R.oy + r * R.th, R.ox + (c + 1) * R.tw, R.oy + (r + 1) * R.th, 'door', {c:c, r:r, key:window.doorKeyAt(R, c, r)})); continue; }
        var f = R.foot ? undefined : window.FURN_SOLID[t];
        if(f !== undefined) boxes.push(toM(cx - R.tw * f / 2, cy - R.th * f / 2, cx + R.tw * f / 2, cy + R.th * f / 2, 'furn', {ch:t}));
      }
    }
    var seen = {};
    if(R.foot) Object.keys(R.foot).forEach(function(k){ R.foot[k].forEach(function(b){
      var key = [b.x0, b.z0, b.x1, b.z1].join(','); if(seen[key]) return; seen[key] = 1;
      boxes.push(box(b.x0, b.z0, b.x1, b.z1, 'foot'));
    }); });
    [['stairExtra', 'stairExtra'], ['propExtra', 'prop']].forEach(function(p){
      (R[p[0]] || []).forEach(function(b){ boxes.push(box(b.x0, b.z0, b.x1, b.z1, p[1])); });
    });
    var spawn = defaultSpawn(R), start = null;
    if(id === window.ClassroomLayout.ownSeat.room) start = seatStart(R);
    var host = window.objById(R.host), shift = window.TeachGallery ? window.TeachGallery.shift(R) : {x:0, y:0};
    var exit = host ? window.doorWorld(host) : null;
    return {
      id:id, name:R.name, host:R.host || null, floor:R.floor === undefined ? null : R.floor,
      cols:R.cols, rows:R.rows, tw:R.tw, th:R.th, ox:R.ox, oy:R.oy, cx:R.cx, cy:R.cy,
      shift:shift, exit_world:exit, grid:grid, spawn:spawn, start:start, seats:seatList(R),
      flags:{principal:!!R.principal, stairwell:!!R.stairwell, spiral:!!R.spiral, custom:!!R.build, collide:!!R.collide, noClock:!!R.noClock, gallery:!!R.gallery, noMap:!!R.noMap,noAnomaly:!!R.noAnomaly},
      walls:mergeCells(walls, R, toM), boxes:boxes, doors:doors, stairs:stairs
    };
  }
  function outLayout(){
    window.SpaceLayout.ensureOutside();
    if(!window.OUT_LAMPS || !window.OUT_LAMPS.length) window.buildOutdoorGeometry();
    var SC = window.SC, B = window.BOUND, boxes = [];
    function toM(x0, y0, x1, y1, kind, extra){ return box(x0 * U, y0 * U, x1 * U, y1 * U, kind, extra); }
    window.OBJ.forEach(function(o){
      if(o.k === 'roof' && !o.open) window.roofSolids(o).forEach(function(q){ boxes.push(toM(q.x0, q.y0, q.x1, q.y1, 'building', {id:o.id})); });
    });
    window.OUT_SOLID.forEach(function(q){ boxes.push(toM(q.x0 * SC, q.y0 * SC, q.x1 * SC, q.y1 * SC, 'solid')); });
    var objs = window.OBJ.map(function(o){ return {id:o.id, k:o.k, x:o.x, y:o.y, w:o.w, h:o.h, door:o.door || null, name:o.n || null, open:!!o.open, open1f:!!o.open1f, door_world:o.k === 'roof' ? window.doorWorld(o) : null}; });
    return {id:'out', SC:SC, U2M:U, TTILE:window.TTILE,
      bound:{x0:(B.x0 + 4) * SC * U, z0:(B.y0 + 4) * SC * U, x1:(B.x1 - 4) * SC * U, z1:(B.y1 - 4) * SC * U},
      boxes:boxes, objects:objs,
      lamps:(window.OUT_LAMPS || []).map(function(l){ return {x:round(l.x), y:round(l.y), z:round(l.z)}; })};
  }
  function campusDoors(){
    var CD = window.CAMPUS_DOOR;
    return CD ? {width:CD.width, annex:CD.annex, doors:CD.doors} : null;
  }
  window.__wdfzLayout = function(kind, id){
    if(kind === 'out') return outLayout();
    if(kind === 'maze') return {cfg:window.MAZE_CFG, air:window.MAZE_AIR, solid:window.MAZE_SOLID,
      walk:window.MAZE_WALK, eggs:window.MAZE_EGG_CFG};
    if(kind === 'campus'){
      var locks = {};
      Object.keys(window.DOOR_LOCKS).forEach(function(k){ var id = window.DOOR_LOCKS[k]; locks[k] = {item:id, name:window.ITEMS[id] ? window.ITEMS[id].n : id}; });
      return {campus_doors:campusDoors(), door_locks:locks, PRAD:window.PRAD, TTILE:window.TTILE, U2M:U, SC:window.SC, EYE:window.EYE, WALLH:window.WALLH,
        SPD_WALK:window.SPD_WALK, SPD_RUN:window.SPD_RUN, start_room:window.ClassroomLayout.ownSeat.room,
        own_seat:window.ClassroomLayout.ownSeat, classroom_rows:window.ClassroomLayout.rows,
        sched:window.SCHED, day_phases:window.DAY_PHASES, lights_out:window.LIGHTS_OUT, evening:window.EVENING,
        pressure_curve:window.CampusPressure.curve, pressure_messages:window.CampusPressure.messages,
        stamina:{back:window.STAM_BACK, run:window.STAM_RUN, rest:window.STAM_REST, snack_sec:window.SNACK_SEC},
        items:window.ITEMS, item_glyph:window.ITEM_GLYPH, desk_loot:window.DESK_LOOT, lab_loot:window.LAB_LOOT,
        pill:{sec:window.PILL_SEC, rate:window.PILL_RATE}, bag_capacity:window.InventoryRules.capacity,
        own_podium:window.ClassroomLayout.podium(window.ClassroomLayout.ownSeat.classId),
        room_lights:window.ROOM_LIGHTS, light_cfg:window.LCFG, sun:{rise:window.SUN_RISE, set:window.SUN_SET}, bound_map:window.BOUND, meals:window.MEALS, gates:{n:window.GATE_N, w:window.GATE_W, s:window.GATE_S},
        stair_layout:window.STAIR_LAYOUT, stair_geometry:window.StairGeometry.config, spiral:window.SPIRAL,
        campus_link:window.CAMPUS_LINK ? {width:window.CAMPUS_LINK.width, annex:window.CAMPUS_LINK.annex, pairs:window.CAMPUS_LINK.pairs} : null,
        reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc'};
    }
    return roomLayout(id);
  };
})();
