/* Dimensions in metres. The classroom side of the corridor wall and the blackboard
   face of each party wall stay on their original layout lines. */
window.NativeCampus = (() => {
  const depth = 0.20;
  function partition(room, x, y) {
    if (room.host !== 'teach' || room.floor < 1 || room.floor > 5) return '';
    const layout = window.ClassroomLayout, spans = layout.spans;
    if (y === layout.rows[1] + 1 && x >= spans[0][0] && x <= spans[spans.length - 1][1]) return 'hall';
    if (y >= layout.rows[0] && y <= layout.rows[1] && spans.slice(1).some(span => x === span[0] - 1)) return 'divider';
    return '';
  }
  function bounds(kind, x0, z0, x1, z1) {
    if (kind === 'hall') z1 = z0 + depth;
    if (kind === 'divider') x0 = x1 - depth;
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

  // Build the outside face around every authored portal. No inner face or solid
  // block can plug the hallway when a far facade and its neighbouring shaft coexist.
  function exteriorWalls(kit, px, pz, width, depth, height, color, openings) {
    for (const face of ['n', 's', 'e', 'w']) {
      const alongX = face === 'n' || face === 's';
      const center = alongX ? px : pz, length = alongX ? width : depth;
      const plane = alongX ? pz + (face === 's' ? 1 : -1) * (depth / 2 - .03)
                           : px + (face === 'e' ? 1 : -1) * (width / 2 - .03);
      const cuts = [];
      for (const op of openings.filter(h => h.face === face)) {
        for (let i = 0; i < op.levels; i++)
          cuts.push({lo: op.lo, hi: op.hi, bottom: i * op.rise, top: i * op.rise + (op.clear || 2.30)});
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
  return {depth, partition, bounds, frame, leaves, spansOutside, stairOpenings, exteriorWalls};
})();
