/* Dimensions in metres. The classroom side of the corridor wall and the blackboard
   face of each party wall stay on their original layout lines. */
window.NativeCampus = (() => {
  const depth = 0.20;
  const layout = window.NATIVE_CAMPUS_LAYOUT;
  const retiredDoors = {};
  const edges = ['n', 'w', 's', 'e'];
  function physicalEdge(edge, turn = 0) {
    return edges[(edges.indexOf(edge) + turn + 4) % 4];
  }
  function bridgeX(building, port) {
    const along = (port.at + .5) * 4.5;
    return building.x + (building.turn === 2 ? building.w - along : along);
  }
  function placeBuildings(objects) {
    const byId = Object.fromEntries(objects.map(o => [o.id, o]));
    for (const [id, placement] of Object.entries(layout.buildings)) {
      if (!byId[id]) throw new Error('Unknown campus building: ' + id);
      Object.assign(byId[id], placement);
    }
    for (const {host, edge} of Object.values(layout.entrances)) byId[host].door = physicalEdge(edge, byId[host].turn);
    for (const {id, name, north, south} of layout.bridges) {
      const bridge = byId[id];
      const a = byId[north.room.slice(0, -1)], b = byId[south.room.slice(0, -1)];
      if (physicalEdge(north.edge || 's', a.turn) !== 's' || physicalEdge(south.edge || 'n', b.turn) !== 'n'
          || bridgeX(a, north) !== bridgeX(b, south) || b.y - (a.y + a.h) !== bridge.h) {
        throw new Error('Misaligned campus bridge: ' + id);
      }
      Object.assign(bridge, {n: name, x: bridgeX(a, north) - bridge.w / 2, y: a.y + a.h});
    }
    objects.push({...layout.plaza});
  }
  function entryApproaches(rooms) {
    for (const [id, entrance] of Object.entries(layout.entrances)) {
      const grid = rooms[id].grid;
      for (const row of grid) for (let i = 0; i < row.length; i++) {
        if (row[i] === 'O') row[i] = '#';
      }
      for (const [left, top, right, bottom] of entrance.clear)
        for (let row = top; row <= bottom; row++)
          for (let col = left; col <= right; col++) grid[row][col] = '.';
    }
  }
  function entryDoors(doors) {
    return doors.flatMap(door => {
      const entry = layout.entrances[door.room];
      if (!entry) return [door];
      retiredDoors[door.room] = {...door, width: door.width || 3};
      const main = {...door, edge: entry.edge, at: entry.at};
      return [main, ...(entry.bays || []).map(bay => ({...main, ...bay}))];
    });
  }
  function doorPoint(object) {
    const doors = window.CampusDoor;
    const entry = doors?.CFG.doors.find(d => d.host === object.id && layout.entrances[d.room]);
    const port = entry && doors.outPort(entry);
    if (!Number.isFinite(port?.x) || !Number.isFinite(port?.y)) return null;
    return {x: port.x + port.n[0] * 26, y: port.y + port.n[1] * 26};
  }
  function bridgePairs() {
    return layout.bridges.flatMap(({id, north, south}) => {
      const room = 'link' + id.slice(1);
      return [
        [{edge:'s', ...north}, {room, edge:'n', at:2}],
        [{edge:'n', ...south}, {room, edge:'s', at:2}]
      ];
    });
  }
  function bridgeApproaches(rooms) {
    for (const [port] of bridgePairs()) {
      const grid = rooms[port.room].grid;
      grid[port.edge === 's' ? grid.length - 2 : 1][port.at] = 'L';
    }
  }
  function teachingColumns(px, pz, width, depth) {
    const shape = window.teachSouth(px, pz, width, depth);
    const x = shape.x0 + (layout.entrances.teach1.at + .5) * shape.t;
    return window.colonnadeColumns(px, pz, width, depth, x).filter(column =>
      !shape.towers.some(tower => Math.abs(column.x - tower.x) < tower.half + .31));
  }
  function teachingTowerBounds(px, pz, width, depth) {
    return window.teachSouth(px, pz, width, depth).towers.map(tower => ({
      x: 2 * px - tower.x, z0: 2 * pz - tower.z1, z1: 2 * pz - tower.z0, half: tower.half
    }));
  }
  function outsidePort(room, port, shift) {
    const turn = window.objById(room.host)?.turn || 0;
    const c = Math.round(Math.cos(turn * Math.PI / 2)), s = Math.round(Math.sin(turn * Math.PI / 2));
    const x = port.x - room.cx, y = port.y - room.cy;
    return {x: room.cx + shift.x + c*x + s*y, y: room.cy + shift.y - s*x + c*y,
      n: [c*port.n[0] + s*port.n[1], -s*port.n[0] + c*port.n[1]]};
  }
  function plazaRoad() {
    const {x, y, w, h} = layout.plaza;
    return [x, y, x + w, y + h];
  }
  function partition(room, x, y) {
    if (room.host === 'c1' || room.host === 'c2') {
      if (x === 0) return 'bridge_w';
      if (x === room.cols - 1) return 'bridge_e';
    }
    if (room.host !== 'teach' || room.floor < 1 || room.floor > 5) return '';
    const layout = window.ClassroomLayout, spans = layout.spans;
    if (y === layout.rows[1] + 1 && x >= spans[0][0] && x <= spans[spans.length - 1][1]) return 'hall';
    if (y >= layout.rows[0] && y <= layout.rows[1] && spans.slice(1).some(span => x === span[0] - 1)) return 'divider';
    return '';
  }
  function bounds(kind, x0, z0, x1, z1) {
    if (kind === 'hall') z1 = z0 + depth;
    if (kind === 'divider' || kind === 'bridge_e') x0 = x1 - depth;
    if (kind === 'bridge_w') x1 = x0 + depth;
    return {x0, z0, x1, z1};
  }
  function frame(kit) {
    const trim = 0x41484b, sill = 0x8c8980;
    for (const side of [-1, 1]) {
      kit.box('metal', side * .47, 1.04, 0, .06, 2.08, depth, trim, 1);
      for (const face of [-1, 1])
        kit.box('metal', side * .49, 1.04, face * (depth / 2 + .009), .08, 2.08, .018, trim, 1);
    }
    kit.box('metal', 0, 2.07, 0, 1.04, .06, depth + .036, trim, 1);
    kit.box('concrete', 0, .006, 0, .90, .012, depth + .035, sill, 1);
  }
  // Convert the same local hinge used by buildDoorLeaf to floor coordinates.
  function leaves(room, x, y, cx, cz) {
    const row = room.grid[y], rightLeaf = row[x - 1] === '=', leftLeaf = row[x + 1] === '=';
    const horizontal = ['#', '='].includes(row[x - 1]) || ['#', '='].includes(row[x + 1]);
    const thin = partition(room, x, y) === 'hall';
    if (thin) cz -= (1 - depth) / 2;
    const z = thin ? .07 : .38, side = rightLeaf ? -1 : 1;
    const hinge = rightLeaf ? .47 : leftLeaf ? -.47 : -.43;
    function rect(a, b, c, d) {
      const xy = horizontal ? [cx + a, cz + b, cx + c, cz + d] : [cx + b, cz - c, cx + d, cz - a];
      return xy.map(n => Math.round(n * 10000) / 10000);
    }
    const end = hinge + side * .86, openX = hinge + side * .03;
    return {closed: rect(Math.min(hinge, end), z - .0225, Math.max(hinge, end), z + .0225),
      open: rect(openX - .0225, z, openX + .0225, z + .86)};
  }
  // Masonry, skirting and rails use exactly the same door openings.
  function spansOutside(left, right, openings) {
    const spans = [];
    let from = left;
    for (const [a, b] of openings.slice().sort((p, q) => p[0] - q[0])) {
      if (a > from && from < right) spans.push([from, Math.min(a, right)]);
      from = Math.max(from, b);
    }
    if (from < right) spans.push([from, right]);
    return spans;
  }
  function stairOpenings(host) {
    return window.STAIR_LAYOUT.filter(stair => stair.host === host).map(stair => {
      const room = window.INTERIORS[stair.rooms[0]];
      const port = window.StairWorld.port(stair, 0), shift = window.TeachGallery.shift(room);
      const face = port.n[0] < 0 ? 'w' : port.n[0] > 0 ? 'e' : port.n[1] > 0 ? 's' : 'n';
      const along = (port.n[0] ? port.y + shift.y : port.x + shift.x) / 9;
      return {face, lo: along - .86, hi: along + .86, rise: stair.rise, levels: stair.rooms.length};
    });
  }
  function bridgeOpenings(host) {
    return layout.bridges.flatMap(({north, south}) => [
      {edge: 's', ...north}, {edge: 'n', ...south},
    ]).filter(port => port.room.slice(0, -1) === host).map(port => {
      const building = window.objById(host);
      const centre = (building.x + (port.at + .5) * 4.5) * window.SC * window.U2M;
      return {face: port.edge, lo: centre - 1.52, hi: centre + 1.52, base: 3.2, rise: 0, levels: 1};
    });
  }
  function entryOpening(o, px, pz) {
    const seam = o.seamDoor;
    if (!seam) return [];
    const face = o.door || 's';
    const centre = (face === 'n' || face === 's' ? px : pz) + (seam.dx || 0);
    const half = seam.width / 2 + .02;
    return [{face, lo: centre - half, hi: centre + half, rise: 0, levels: 1, clear: 2.32}];
  }

  // Build the outside face around every authored portal. No inner face or solid
  // block can plug the hallway when a far facade and its neighbouring shaft coexist.
  function exteriorWalls(kit, px, pz, width, depth, height, color, openings, faces = ['n', 's', 'e', 'w']) {
    for (const face of faces) {
      const alongX = face === 'n' || face === 's';
      const center = alongX ? px : pz, length = alongX ? width : depth;
      const plane = alongX ? pz + (face === 's' ? 1 : -1) * (depth / 2 - .03)
                           : px + (face === 'e' ? 1 : -1) * (width / 2 - .03);
      const cuts = [];
      for (const op of openings.filter(h => h.face === face)) {
        for (let i = 0; i < op.levels; i++) {
          const bottom = (op.base || 0) + i * op.rise;
          cuts.push({lo: op.lo, hi: op.hi, bottom, top: bottom + (op.clear || 2.30)});
        }
      }
      const levels = [...new Set([0, height, ...cuts.flatMap(c => [c.bottom, c.top]).filter(y => y > 0 && y < height)])].sort((a,b) => a-b);
      for (let i = 1; i < levels.length; i++) {
        const y0 = levels[i-1], y1 = levels[i], mid = (y0+y1)/2;
        const gaps = cuts.filter(c => c.bottom < mid && c.top > mid).map(c => [c.lo, c.hi]);
        for (const [lo, hi] of spansOutside(center-length/2, center+length/2, gaps)) {
          const u = (lo+hi)/2;
          kit.g('brick').boxFaces(alongX ? u : plane, mid, alongX ? plane : u,
            alongX ? hi-lo : .06, y1-y0, alongX ? .06 : hi-lo, color, .97, face);
        }
      }
    }
  }
  function bridgeWalls(kit, halfWidth, halfLength, ceiling, wallMaterial, wallColor) {
    const sill = .90, head = 2.40, bayWidth = 2.0;
    for (const side of [-1, 1]) {
      const x = side * (halfWidth - depth / 2);
      kit.box(wallMaterial, x, sill / 2, 0, depth, sill, halfLength * 2, wallColor, .95);
      kit.box(wallMaterial, x, (head + ceiling) / 2, 0, depth, ceiling - head, halfLength * 2, wallColor, .95);
      for (let z = -halfLength + bayWidth / 2; z < halfLength; z += bayWidth) {
        kit.box('glass', x, (sill + head) / 2, z, .025, head - sill, bayWidth, 0x95aeb3, 1);
        kit.box('metal', x, (sill + head) / 2, z - bayWidth / 2 + .04, depth, head - sill, .08, 0x383f43, 1);
        kit.box('metal', x, sill + .035, z, depth, .07, bayWidth, 0x383f43, 1);
        kit.box('metal', x, head - .035, z, depth, .07, bayWidth, 0x383f43, 1);
      }
      kit.box('metal', x, (sill + head) / 2, halfLength - .04, depth, head - sill, .08, 0x383f43, 1);
    }
  }
  function stairExterior(kit, stair, brick, trim) {
    if (stair.rooms.includes('out')) return;
    const room = window.INTERIORS[stair.rooms[0]];
    const port = outsidePort(room, window.StairWorld.port(stair, 0), window.TeachGallery.shift(room));
    const x = port.x / 9 + port.n[0] * 2.8;
    const z = port.y / 9 + port.n[1] * 2.8;
    const frame = kit.sub(x, z, Math.atan2(port.n[0], port.n[1]), 0);
    const front = -2.8, back = 7.38, half = 2.38;
    const height = (stair.rooms.length - 1) * stair.rise + 3.0;
    const length = back - front, center = (front + back) / 2;
    // The brick skin sits just outside the native shaft's plaster and landings.
    const masonry = kit.g('brick');
    for (const side of [-1, 1])
      masonry.boxFaces(side * (half - .02), height / 2, center, .04, height, length, brick, .97, side < 0 ? 'w' : 'e');
    masonry.boxFaces(0, height / 2, back - .02, half * 2, height, .04, brick, .97, 's');
    for (const side of [-1, 1])
      masonry.boxFaces(side * (half + .86) / 2, height / 2, front + .02, half - .86, height, .04, brick, .97, 'n');
    for (let level = 0; level < stair.rooms.length; level++) {
      const lo = level * stair.rise + 2.30;
      const hi = Math.min(height, (level + 1) * stair.rise);
      masonry.boxFaces(0, (lo + hi) / 2, front + .02, 1.72, hi - lo, .04, brick, .97, 'n');
    }
    kit.box('plaster', 0, height + .10, center, half * 2 + .14, .20, length + .14, trim, 1);
    // A narrow louvred panel marks each enclosed landing; the shaft still has its solid inner wall.
    for (let y = 2.5; y < height - .7; y += stair.rise) {
      kit.box('metal', 0, y, back + .03, 1.18, .58, .06, 0x494e52, 1);
      for (let row = -1; row <= 1; row++)
        kit.box('metal', 0, y + row * .14, back + .067, 1.05, .044, .035, 0x7f8585, 1);
    }
    kit.restore(frame);
  }
  return {depth, partition, bounds, frame, leaves, spansOutside, stairOpenings, bridgeOpenings, entryOpening,
    exteriorWalls, bridgeWalls, stairExterior, placeBuildings, entryApproaches, entryDoors, doorPoint, retiredDoors,
    bridgePairs, bridgeApproaches, outsidePort, plazaRoad, teachingColumns, teachingTowerBounds};
})();
