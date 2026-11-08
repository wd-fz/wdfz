// Evaluate only in the pinned original runtime, never in the port.
() => {
  const offers=[];
  for(const room of ['teach1','teach2','lab1'])for(const cell of [[59,18],[58,16],[61,19],[57,18],[62,18],[59,20]])
    for(const t of [705,705+14/60-1e-6,705+14/60,705+14.5/60,705+15/60,706]) {
      freshState('hard');
      const r=INTERIORS[room];
      Object.assign(S,{room,mode:'in',x:r.ox+(cell[0]+.5)*r.tw,y:r.oy+(cell[1]+.5)*r.th,tsec:t,bag:['coin'],bagSel:0});
      dropSelected();
      offers.push({room,cell,t,unlocked:!!RT.beastDrop,bag:S.bag.slice()});
    }
  const frames=[];
  const oldLook=cutLook,oldFade=cutFade;
  try {
    let view=[],fade=0;
    cutLook=(...args)=>{view=args;GLR.cam.position.set(args[0],args[1],args[2]);};
    cutFade=k=>{fade=k;};
    for(const shake of [false,true]) {
      SHAKE_ON=shake;
      const d={light:{material:{opacity:0}},fig:new THREE.Object3D()};
      for(let i=0;i<=180;i++) {
        const k=i/180;
        CUT_DEF.beast.frame(k,d);
        frames.push({k,shake,view,fade,normal:GLR.worldNorm,figure:d.fig.position.toArray(),visible:d.fig.visible,light:d.light.material.opacity});
      }
    }
  } finally {cutLook=oldLook;cutFade=oldFade;}
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',offers,frames};
}
